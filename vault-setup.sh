#!/bin/bash
# Vault Setup Script KUBERNETES

PUB=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
VNS=kube-vault

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

# Install Cfssl
if ! command -v cfssl &> /dev/null;
then
 echo "Installing Cfssl"
 curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl_1.6.0_linux_amd64
 chmod +x cfssl
 mv cfssl /usr/local/bin/
fi

# Install Cfssljson
if ! command -v cfssljson &> /dev/null;
then
 echo "Installing Cfssljson"
 curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssljson_1.6.0_linux_amd64
 chmod +x cfssljson
 mv cfssljson /usr/local/bin/
fi

# Install GIT
if ! command -v git &> /dev/null;
then
 echo "Installing GIT"
 yum install git -y
fi

# Checking repo
if [ ! -d "k8s-vault" ]; then
 git clone https://github.com/cloudcafetech/k8s-vault.git
fi
find ./k8s-vault/ -type f -exec sed -i -e "s/172.31.14.138/$HIP/g" {} \;
find ./k8s-vault/ -type f -exec sed -i -e "s/3.16.154.209/$PUB/g" {} \;
cd k8s-vault

# Certificate Generate
cfssl gencert -initca certs/config/ca-csr.json | cfssljson -bare certs/ca

cfssl gencert \
    -ca=certs/ca.pem \
    -ca-key=certs/ca-key.pem \
    -config=certs/config/ca-config.json \
    -profile=default \
    certs/config/consul-csr.json | cfssljson -bare certs/consul

cfssl gencert \
    -ca=certs/ca.pem \
    -ca-key=certs/ca-key.pem \
    -config=certs/config/ca-config.json \
    -profile=default \
    certs/config/vault-csr.json | cfssljson -bare certs/vault
cp certs/vault.pem certs/tls.crt
cp certs/vault-key.pem certs/tls.key

# Create Namespace
kubectl create ns $VNS

# Setup Consul
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault-backend hashicorp/consul -f override/consul-acl.yaml --namespace $VNS

# setup Vault
TOKEN=`kubectl get secret vault-backend-consul-bootstrap-acl-token -n $VNS -o template --template '{{.data.token}}'|base64 -d`

#Add this token to Vault override
sed -i "s/dummytoken/$TOKEN/g" vault/vault.yaml

# Altering namespace
sed -i "s/namespace: kube-vault/namespace: $VNS/g" vault/vault.yaml

#Finally install Vault
kubectl create secret generic vault-vault-cert-active -n $VNS \
    --from-file=certs/ca.pem \
    --from-file=certs/tls.crt \
    --from-file=certs/tls.key
kubectl create -f vault/vault.yaml -n $VNS

# Setup Ingress
kubectl create -f vault/ingress.yaml -n $VNS
