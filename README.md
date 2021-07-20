# Running Vault and Consul on Kubernetes

## Want to learn how to build this?

Check out the [post](https://testdriven.io/running-vault-and-consul-on-kubernetes).

## Want to use this project?

### Prerequisites

Install reuired tools:

- KIND

```sh
$ echo "Installing Kind"
$ curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.10.0/kind-linux-amd64
$ chmod +x ./kind
$ mv ./kind /usr/local/bin/kind
```

- Kubectl

```sh
$ echo "Installing Kubectl"
$ K8S_VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
$ wget -q https://storage.googleapis.com/kubernetes-release/release/$K8S_VER/bin/linux/amd64/kubectl
$ chmod +x ./kubectl
$ mv ./kubectl /usr/bin/kubectl
$ echo "alias oc=/usr/bin/kubectl" >> /root/.bash_profile
```

- Consul

```sh
$ curl https://releases.hashicorp.com/consul/1.9.8/consul_1.9.8_linux_amd64.zip -o consul_1.9.8_linux_amd64.zip
$ unzip consul_1.9.8_linux_amd64.zip
$ chmod +x consul
$ mv consul /usr/local/bin/consul
$ rm -rf consul_1.9.8_linux_amd64.zip
```

- Vault

```sh
$ curl https://releases.hashicorp.com/vault/1.7.3/vault_1.7.3_linux_amd64.zip -o vault_1.7.3_linux_amd64.zip
$ unzip vault_1.7.3_linux_amd64.zip
$ chmod +x vault
$ mv vault /usr/local/bin/vault
$ rm -rf vault_1.7.3_linux_amd64.zip
```

- Cfssl & Cfssljson

```sh
$ curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl_1.6.0_linux_amd64
$ curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssljson_1.6.0_linux_amd64
$ curl -s -L -o cfssl-certinfo https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl-certinfo_1.6.0_linux_amd64
$ chmod +x cfssl*
$ mv cfssl* /usr/local/bin/
```

### KIND (Kubernetes in Docker)

Start the cluster:

```sh
$ kind create cluster --config kind-kube-install.yaml
```

### TLS Certificates

Create a Certificate Authority:

```sh
$ cfssl gencert -initca certs/config/ca-csr.json | cfssljson -bare certs/ca
```

Create the private keys and TLS certificates:

```sh
$ cfssl gencert \
    -ca=certs/ca.pem \
    -ca-key=certs/ca-key.pem \
    -config=certs/config/ca-config.json \
    -profile=default \
    certs/config/consul-csr.json | cfssljson -bare certs/consul

$ cfssl gencert \
    -ca=certs/ca.pem \
    -ca-key=certs/ca-key.pem \
    -config=certs/config/ca-config.json \
    -profile=default \
    certs/config/vault-csr.json | cfssljson -bare certs/vault
```

### Vault and Consul

Spin up Vault and Consul on Kubernetes:

```sh
$ sh create.sh
```

### Environment Variables

In a new terminal window, navigate to the project directory and set the following environment variables:

```sh
$ export VAULT_ADDR=https://127.0.0.1:8200
$ export VAULT_CACERT="certs/ca.pem"
```

### Verify

```sh
$ kubectl get pods
$ vault status
```
