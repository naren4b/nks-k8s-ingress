# Check if the directory exists
SERVICE_NAME=$1
ROOT_CERT_DIR=$2

if [ -z "$ENV_ROOT_DOMAIN" ];then
 export ENV_ROOT_DOMAIN=naren4biz.in
fi

if [ -d "$ROOT_CERT_DIR" ]; then
    echo "Directory exists: $DIRECTORY_PATH"
else
    mkdir -p $ROOT_CERT_DIR
fi

# Check if the file exists
if [ -f "$ROOT_CERT_DIR/rootCA.key" ]; then
    ls -lrt $ROOT_CERT_DIR
else
    
    openssl req -x509 -sha256 -newkey rsa:2048  -keyout $ROOT_CERT_DIR/rootCA.key -out $ROOT_CERT_DIR/rootCA.crt \
                -days 356 -nodes -subj "/C=IN/ST=Karnataka/L=Bangalore/O=Naren/CN=${ENV_ROOT_DOMAIN}"
    ls -lrt $ROOT_CERT_DIR
fi

if [ -f "$ROOT_CERT_DIR/domain.ext" ]; then
    ls -lrt $ROOT_CERT_DIR
else

cat >$ROOT_CERT_DIR/domain.ext <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
subjectAltName = @alt_names
[alt_names]
DNS.1 = *.$ENV_ROOT_DOMAIN
EOF

fi

SERVICE_CERT_DIR=$ROOT_CERT_DIR/$SERVICE_NAME
rm -rf $SERVICE_CERT_DIR
mkdir -p $SERVICE_CERT_DIR


openssl req -new -newkey rsa:2048 -keyout $SERVICE_CERT_DIR/${SERVICE_NAME}.key -out $SERVICE_CERT_DIR/${SERVICE_NAME}.csr -nodes -subj "/CN=${SERVICE_NAME}"
openssl x509 -req -CA $ROOT_CERT_DIR/rootCA.crt -CAkey $ROOT_CERT_DIR/rootCA.key \
                  -days 365  -set_serial 01 -CAcreateserial -extfile $ROOT_CERT_DIR/domain.ext \
                  -in $SERVICE_CERT_DIR/${SERVICE_NAME}.csr -out $SERVICE_CERT_DIR/${SERVICE_NAME}.crt 
