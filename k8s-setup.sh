#!/bin/bash
# Install KIND KUBERNETES

CLUSTER0=kube-central

PUB=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
MinIO=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
velver=v1.4.2

# Install packages
echo "Installing Packges"
yum install -q -y git curl wget bind-utils jq httpd-tools zip unzip nfs-utils dos2unix telnet java-1.8.0-openjdk

# Install Docker
if ! command -v docker &> /dev/null;
then
  echo "MISSING REQUIREMENT: docker engine could not be found on your system. Please install docker engine to continue: https://docs.docker.com/get-docker/"
  echo "Trying to Install Docker..."
  if [[ $(uname -a | grep amzn) ]]; then
    echo "Installing Docker for Amazon Linux"
    amazon-linux-extras install docker -y
    systemctl enable docker;systemctl start docker
    docker ps -a
  else
    curl -s https://releases.rancher.com/install-docker/19.03.sh | sh
    systemctl enable docker;systemctl start docker
    docker ps -a
  fi    
fi


# Install KIND
if ! command -v kind &> /dev/null;
then
 echo "Installing Kind"
 curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.10.0/kind-linux-amd64
 chmod +x ./kind; mv ./kind /usr/local/bin/kind
fi

# Install Kubectl
if ! command -v kubectl &> /dev/null;
then
 echo "Installing Kubectl"
 K8S_VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
 wget -q https://storage.googleapis.com/kubernetes-release/release/$K8S_VER/bin/linux/amd64/kubectl
 chmod +x ./kubectl; mv ./kubectl /usr/bin/kubectl
 echo "alias oc=/usr/bin/kubectl" >> /root/.bash_profile
fi 

# Install Consul
if ! command -v consul &> /dev/null;
then
 echo "Installing Consul"
 curl https://releases.hashicorp.com/consul/1.9.8/consul_1.9.8_linux_amd64.zip -o consul_1.9.8_linux_amd64.zip
 unzip consul_1.9.8_linux_amd64.zip
 chmod +x consul
 mv consul /usr/local/bin/consul
 rm -rf consul_1.9.8_linux_amd64.zip
fi

# Install Vault
if ! command -v vault &> /dev/null;
then
 echo "Installing Vault"
 curl https://releases.hashicorp.com/vault/1.7.3/vault_1.7.3_linux_amd64.zip -o vault_1.7.3_linux_amd64.zip
 unzip vault_1.7.3_linux_amd64.zip
 chmod +x vault
 mv vault /usr/local/bin/vault
 rm -rf vault_1.7.3_linux_amd64.zip
fi

# Install Cfssl & Cfssljson
curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl_1.6.0_linux_amd64
curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssljson_1.6.0_linux_amd64
curl -s -L -o cfssl-certinfo https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl-certinfo_1.6.0_linux_amd64
chmod +x cfssl*
mv cfssl* /usr/local/bin/

# Clone Git
git clone https://github.com/prasenforu/CLT.git
wget https://raw.githubusercontent.com/prasenforu/CLT/main/kube-kind-ingress.yaml

# Kubernetes Cluster Creation
for CTX in $CLUSTER0
do
cat <<EOF > kind-kube-$CTX.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerPort: 19091
  apiServerAddress: $HIP
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 80
  - containerPort: 30443
    hostPort: 443
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
EOF
done

# Cluster Creation

kind create cluster --name $CLUSTER0 --kubeconfig $CLUSTER0-kubeconf --config kind-kube-$CLUSTER0.yaml --wait 2m

# Setup Helm Chart
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh

# Setup Ingress
echo "Setting Ingress for $CLUSTER0"
export KUBECONFIG=$CLUSTER0-kubeconf
kubectl apply -f kube-kind-ingress.yaml
sleep 15
kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission

cp $CLUSTER0-kubeconf .kube/config


# Install Krew
set -x; cd "$(mktemp -d)" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.{tar.gz,yaml}" &&
  tar zxvf krew.tar.gz &&
  KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" &&
  "$KREW" install --manifest=krew.yaml --archive=krew.tar.gz &&
  "$KREW" update

export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

kubectl krew install modify-secret
kubectl krew install ctx
kubectl krew install ns
kubectl krew install cost

echo 'export PATH="${PATH}:${HOME}/.krew/bin"' >> /root/.bash_profile
exit
