#!/bin/zsh
# Maakt eenmalig het certificaat "CastBar Local Signing" in de login-sleutelhanger.
# Daarmee ondertekend blijft het Toegankelijkheid-vinkje van CastBar geldig na een nieuwe build.
set -e
NAME="CastBar Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "certificaat bestaat al: $NAME"; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf $TMP' EXIT
PASS=$(openssl rand -hex 16)
cat > $TMP/cert.cnf <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout $TMP/key.pem -out $TMP/cert.pem -days 3650 -config $TMP/cert.cnf 2>/dev/null
openssl pkcs12 -export -inkey $TMP/key.pem -in $TMP/cert.pem -out $TMP/cert.p12 -passout pass:$PASS -name "$NAME"
security import $TMP/cert.p12 -k ~/Library/Keychains/login.keychain-db -P $PASS -T /usr/bin/codesign
echo "certificaat aangemaakt: $NAME"
