#!/bin/bash
# Enable Vault KUBERNETES Auth

VNS=kube-vault
export VAULT_ADDR=http://vault-internal.172.31.18.255.nip.io/
export VAULT_TOKEN=s.EsgrrtPlNsG6Dqh2u9QZIXAL

cat <<EOF > vault-auth.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: $VNS
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
  namespace: kube-vault
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: $VNS
EOF

# Set VAULT_SA_NAME to the service account you created earlier
export VAULT_SA_NAME=$(kubectl get sa vault-auth -n $VNS -o jsonpath="{.secrets[*]['name']}")

# Set SA_JWT_TOKEN value to the service account JWT used to access the TokenReview API
export SA_JWT_TOKEN=$(kubectl get secret $VAULT_SA_NAME -n $VNS -o jsonpath="{.data.token}" | base64 --decode; echo)

# Set SA_CA_CRT to the PEM encoded CA cert used to talk to Kubernetes API
export SA_CA_CRT=$(kubectl get secret $VAULT_SA_NAME -n $VNS -o jsonpath="{.data['ca\.crt']}" | base64 --decode; echo)

# Enable Kubernetes as auth
export K8S_HOST="https://kubernetes.default.svc:443"
vault auth enable --tls-skip-verify kubernetes
vault write --tls-skip-verify auth/kubernetes/config token_reviewer_jwt="$SA_JWT_TOKEN" kubernetes_host="$K8S_HOST" kubernetes_ca_cert="$SA_CA_CRT"
