# Running Vault and Consul on Kubernetes

Highly-available (HA) Hashicorp Vault and Consul cluster on Kubernetes with TLS.

### Prerequisites

Install reuired tools:

- KIND

```
echo "Installing Kind"
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.10.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind
```

- Kubectl

```
echo "Installing Kubectl"
K8S_VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
wget -q https://storage.googleapis.com/kubernetes-release/release/$K8S_VER/bin/linux/amd64/kubectl
chmod +x ./kubectl
mv ./kubectl /usr/bin/kubectl
echo "alias oc=/usr/bin/kubectl" >> /root/.bash_profile
```

- Consul

```
curl https://releases.hashicorp.com/consul/1.9.8/consul_1.9.8_linux_amd64.zip -o consul_1.9.8_linux_amd64.zip
unzip consul_1.9.8_linux_amd64.zip
chmod +x consul
mv consul /usr/local/bin/consul
rm -rf consul_1.9.8_linux_amd64.zip
```

- Vault

```
curl https://releases.hashicorp.com/vault/1.7.3/vault_1.7.3_linux_amd64.zip -o vault_1.7.3_linux_amd64.zip
unzip vault_1.7.3_linux_amd64.zip
chmod +x vault
mv vault /usr/local/bin/vault
rm -rf vault_1.7.3_linux_amd64.zip
```

- Cfssl & Cfssljson

```
curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl_1.6.0_linux_amd64
curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssljson_1.6.0_linux_amd64
curl -s -L -o cfssl-certinfo https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl-certinfo_1.6.0_linux_amd64
chmod +x cfssl*
mv cfssl* /usr/local/bin/
```

### KIND (Kubernetes in Docker)

Start the cluster:

```
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
cat <<EOF > kind-kube-install.yaml
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
kind create cluster --name kube-central --kubeconfig kube-central-kubeconf --config kind-kube-install.yaml --wait 2m
```

### TLS Certificates

Create a Certificate Authority:

```
cfssl gencert -initca certs/config/ca-csr.json | cfssljson -bare certs/ca
```

Create the private keys and TLS certificates:

```
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
```

### Vault & Consul, Vault & Injector Setup

- First deploy Consul

```
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault-backend hashicorp/consul -f override/consul-acl.yaml
```

- Extract the generated ACL token

```TOKEN=`kubectl get secret vault-backend-consul-bootstrap-acl-token -o template --template '{{.data.token}}'|base64 -d` ```

- Add this token to Vault override

```sed -i "s/dummytoken/$TOKEN/g" vault/vault.yaml```

- Finally install Vault

```
kubectl create secret generic vault-vault-cert-active \
    --from-file=certs/ca.pem \
    --from-file=certs/tls.crt \
    --from-file=certs/tls.key
kubectl create -f vault.yaml
```

- Initialize Vault

```kubectl exec -it vault-0 -- sh -c "vault operator init -key-shares=1 -key-threshold=1 -tls-skip-verify" > vault-data```

- Unseal Vault

```
kubectl exec -it vault-0 -- sh -c "vault operator unseal -tls-skip-verify"
kubectl exec -it vault-1 -- sh -c "vault operator unseal -tls-skip-verify"
kubectl exec -it vault-2 -- sh -c "vault operator unseal -tls-skip-verify"
```


### Environment Variables

In a new terminal window, navigate to the project directory and set the following environment variables:

```
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT="certs/ca.pem"
```

### Verify

```
kubectl get pods
vault status
```

## Reference

Check out the [post](https://testdriven.io/running-vault-and-consul-on-kubernetes).
