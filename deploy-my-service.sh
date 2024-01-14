
SERVICE_NAME=$(echo "$1" | tr '[:upper:]' '[:lower:]')
SECURE_SERVICE=true

if [ -z "$ENV_ROOT_DOMAIN" ];then
 export ENV_ROOT_DOMAIN=naren4biz.in
fi

for arg in "$@"; do
    if [ "$arg" == "-insecure" ]; then
      SECURE_SERVICE=false
    fi
  
done

if [ -z "$SERVICE_NAME" ];then
 echo "Invalid Service Name "
 exit
fi
echo SERVICE: $SERVICE_NAME SECURE: $SECURE_SERVICE 

rm -rf $SERVICE_NAME
mkdir $SERVICE_NAME

cat > ${SERVICE_NAME}/pod.yaml <<EOF 
kind: Pod
apiVersion: v1
metadata:
  name: ${SERVICE_NAME}
  labels:
    app: ${SERVICE_NAME}
spec:
  containers:
  - name: ${SERVICE_NAME}
    image: hashicorp/http-echo:0.2.3
    args:
    - "-text=${SERVICE_NAME}"
EOF

cat > ${SERVICE_NAME}/svc.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: ${SERVICE_NAME}
spec:
  selector:
    app: ${SERVICE_NAME}
  ports:
  - port: 5678 
EOF

cat > ${SERVICE_NAME}/ing.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${SERVICE_NAME}
  annotations:
    kubernetes.io~1ingress.class: "nginx"   
spec:
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
EOF


if [ "$SECURE_SERVICE" == true ];then  

ROOT_CERT_DIR="/tmp/mycrts"
SERVICE_CERT_DIR=$ROOT_CERT_DIR/$SERVICE_NAME
bash setupmyorg.sh $SERVICE_NAME $ROOT_CERT_DIR

cat >> ${SERVICE_NAME}/ing.yaml <<EOF
  tls:
  - hosts:
      - ${SERVICE_NAME}.$ENV_ROOT_DOMAIN
    secretName: ${SERVICE_NAME}-tls  

EOF

kubectl create secret generic ${SERVICE_NAME}-tls \
            --from-file=tls.crt=$SERVICE_CERT_DIR/${SERVICE_NAME}.crt \
            --from-file=tls.key=$SERVICE_CERT_DIR/${SERVICE_NAME}.key \
            --from-file=ca.crt=$ROOT_CERT_DIR/rootCA.crt  -o yaml --dry-run=client > ${SERVICE_NAME}/secret.yaml
fi


# Extra for mtls setup 
MTLS=true
NS=default

if [ "$MTLS" == true ];then 
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


fi

echo Notes: 

export ENV_ROOT_DOMAIN=naren4biz.in
ls -lrt ${SERVICE_NAME}
echo "kubectl apply -f ${SERVICE_NAME}"
echo "curl -vk https://${SERVICE_NAME}.$ENV_ROOT_DOMAIN"
ROOT_CERT_DIR="/tmp/mycrts"
SERVICE_CERT_DIR=$ROOT_CERT_DIR/$SERVICE_NAME
echo curl -Lk --cacert $ROOT_CERT_DIR/rootCA.crt  --key $SERVICE_CERT_DIR/${SERVICE_NAME}.key  --cert $SERVICE_CERT_DIR/${SERVICE_NAME}.crt  https://${SERVICE_NAME}.$ENV_ROOT_DOMAIN





