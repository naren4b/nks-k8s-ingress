#!/bin/bash
# bash run.sh <service-name>

wget https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml 
kubectl label nodes controlplane ingress-ready="true"
kubectl apply -f deploy.yaml 
kubectl wait --for=condition=ready pod -n ingress-nginx -l app.kubernetes.io/component=controller

ENV_ROOT_DOMAIN=127.0.0.1.nip.io

ROOT_CERT_DIR="/tmp/mycrts"
mkdir -p $ROOT_CERT_DIR

SERVICE_NAME=$1
mkdir -p $SERVICE_NAME

SERVICE_CERT_DIR=$ROOT_CERT_DIR/$SERVICE_NAME
mkdir -p $SERVICE_CERT_DIR


# Root CA
openssl req -x509 -sha256 -newkey rsa:2048  -keyout $ROOT_CERT_DIR/rootCA.key -out $ROOT_CERT_DIR/rootCA.crt \
                -days 356 -nodes -subj "/C=IN/ST=Karnataka/L=Bangalore/O=Naren/CN=${ENV_ROOT_DOMAIN}"

# Client key and csr
openssl req -new -newkey rsa:2048 -keyout $SERVICE_CERT_DIR/${SERVICE_NAME}.key -out $SERVICE_CERT_DIR/${SERVICE_NAME}.csr -nodes -subj "/CN=${SERVICE_NAME}"

cat >$ROOT_CERT_DIR/domain.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.$ENV_ROOT_DOMAIN
EOF

#Sign Client csr and generate crt

openssl x509 -req -CA $ROOT_CERT_DIR/rootCA.crt -CAkey $ROOT_CERT_DIR/rootCA.key \
                  -days 365  -set_serial 01 -CAcreateserial -extfile $ROOT_CERT_DIR/domain.ext \
                  -in $SERVICE_CERT_DIR/${SERVICE_NAME}.csr -out $SERVICE_CERT_DIR/${SERVICE_NAME}.crt


# Deploy http-echo:0.2.3 service (pod,svc,ing)
kubectl run $SERVICE_NAME --image hashicorp/http-echo:0.2.3 -- -text="Hello $SERVICE_NAME"
kubectl expose pod $SERVICE_NAME --port 5678
kubectl create secret generic ${SERVICE_NAME}-tls \
            --from-file=tls.crt=$SERVICE_CERT_DIR/${SERVICE_NAME}.crt \
            --from-file=tls.key=$SERVICE_CERT_DIR/${SERVICE_NAME}.key \
            --from-file=ca.crt=$ROOT_CERT_DIR/rootCA.crt  -o yaml --dry-run=client > ${SERVICE_NAME}/secret.yaml
NS=default
cat > ${SERVICE_NAME}/ing.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${SERVICE_NAME}
  annotations:
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-secret: "${NS}/${SERVICE_NAME}-tls"
    nginx.ingress.kubernetes.io/auth-tls-error-page: "https://$ENV_ROOT_DOMAIN/error.html"
    nginx.ingress.kubernetes.io/auth-tls-verify-depth: "1"
    nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: ${SERVICE_NAME}.$ENV_ROOT_DOMAIN
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: ${SERVICE_NAME}
            port:
              number: 5678
  tls:
  - hosts:
      - ${SERVICE_NAME}.$ENV_ROOT_DOMAIN
    secretName: ${SERVICE_NAME}-tls
EOF
kubectl apply -f ${SERVICE_NAME}/secret.yaml
kubectl apply -f ${SERVICE_NAME}/ing.yaml

echo curl -L --cacert $ROOT_CERT_DIR/rootCA.crt  --key $SERVICE_CERT_DIR/${SERVICE_NAME}.key  --cert $SERVICE_CERT_DIR/${SERVICE_NAME}.crt  https://${SERVICE_NAME}.$ENV_ROOT_DOMAIN

echo "127.0.0.1 ${SERVICE_NAME}.$ENV_ROOT_DOMAIN" >> /etc/hosts
