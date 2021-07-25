#!/bin/bash
# Vault HA Setup Script KUBERNETES

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

mkdir vault-setup
cd vault-setup

# Download reuired files
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/cert-generate.sh
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/vault-kube-enable.sh
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/vault.yaml
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/consul.yaml
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/vault-autounseal.yaml
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/vault-agent-injector.yaml
wget https://raw.githubusercontent.com/cloudcafetech/k8s-vault/main/ingress.yaml

# Making all scripts executable
chmod +x *.sh

# Certificate Generate
./cert-generate.sh

# Create Namespace
kubectl create ns $VNS

# Setup Consul
sed -i "s/namespace: kube-vault/namespace: $VNS/g" consul.yaml
sed -i "s/k8s-namespace=kube-vault/k8s-namespace=$VNS/g" consul.yaml
kubectl create -f consul.yaml -n $VNS
echo "Waiting Consul to be ready state"
kubectl wait pods/vault-backend-consul-server-0 --for=condition=Ready --timeout=5m -n $VNS
kubectl wait pods/vault-backend-consul-server-1 --for=condition=Ready --timeout=5m -n $VNS
kubectl wait pods/vault-backend-consul-server-2 --for=condition=Ready --timeout=5m -n $VNS
kubectl wait job/vault-backend-consul-server-acl-init --for=condition=complete --timeout=5m -n $VNS

# Setup Vault
TOKEN=`kubectl get secret vault-backend-consul-bootstrap-acl-token -n $VNS -o template --template '{{.data.token}}'|base64 -d`
sed -i "s/dummytoken/$TOKEN/g" vault.yaml
sed -i "s/namespace: kube-vault/namespace: $VNS/g" vault.yaml
kubectl create secret generic vault-vault-cert-active -n $VNS \
  --from-file=tls/ca.crt \
  --from-file=tls.crt=tls/vault-combined.crt \
  --from-file=tls.key=tls/vault.key

# Setup Ingress
kubectl create -f ingress.yaml -n $VNS

# Remove # in front of exit (in next line) to stop here
#exit

# Initialize Vault
echo "Waiting Vault to be ready state"
kubectl wait pods/vault-0 --for=condition=Ready --timeout=5m -n $VNS
kubectl wait pods/vault-1 --for=condition=Ready --timeout=5m -n $VNS
kubectl wait pods/vault-2 --for=condition=Ready --timeout=5m -n $VNS
echo  "Initialize Vault"
kubectl exec -it vault-0 -n $VNS -- sh -c "vault operator init -key-shares=1 -key-threshold=1 -tls-skip-verify" | tee vault-secret
sleep 5

# Removing Binary Character
perl -pe 's/\x1b\[[0-9;]*[mG]//g' vault-secret > vault-data
dos2unix vault-data

# Auto Unsealed Vault
echo  "Setting up Auto Unsealed Vault"
KEYS=`more vault-data | grep Unseal | cut -d ":" -f2 | cut -d " " -f2`
sed -i "s|DUMMY-UNSEAL-KEY|$KEYS|g" vault-autounseal.yaml
dos2unix vault-autounseal.yaml
kubectl create -f vault-autounseal.yaml -n $VNS
echo "Waiting for Vault Auto Unsealed POD ready .."
VASPOD=$(kubectl get pod -n $VNS | grep vault-autounseal | awk '{print $1}')
kubectl wait pods/$VASPOD --for=condition=Ready --timeout=5m -n $VNS
sleep 5
kubectl delete po vault-0 -n $VNS --force

# Uploading data (root-token & unseal-key) to Consul for safe backup
TOKEN=`kubectl get secret vault-backend-consul-bootstrap-acl-token -n $VNS -o template --template '{{.data.token}}'|base64 -d`
ROOT_TOKEN=`more vault-data | grep Token | cut -d ":" -f2 | cut -d " " -f2`
CONSUL=`kubectl get ing consul -n $VNS | grep consul-internal | cut -d "," -f2 | awk '{print $1}'`
curl --header "Authorization: Bearer $TOKEN" --request PUT -d "$KEYS" http://$CONSUL/v1/kv/unseal-key
curl --header "Authorization: Bearer $TOKEN" --request PUT -d "$ROOT_TOKEN" http://$CONSUL/v1/kv/root-token
