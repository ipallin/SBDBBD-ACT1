#!/usr/bin/env bash
set -euo pipefail

# Script para generar una CA local y certs de servidor para desarrollo
# Salida esperada en este mismo directorio:
# - ca.key   (clave privada CA)
# - ca.pem   (certificado CA)
# - cert.key (clave privada servidor/fastapi)
# - cert.crt (certificado servidor firmado por la CA)
# - mongo.pem (archivo PEM combinado con clave privada + cert para MongoDB)

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
cd "$WORKDIR"

if [[ -f ca.pem && -f cert.crt && -f cert.key && -f mongo.pem ]]; then
  echo "Certificados ya existen en $WORKDIR — saliendo sin cambios."
  exit 0
fi

echo "Generando CA (ca.key, ca.pem)..."
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 \
  -subj "/C=US/ST=Local/L=Local/O=Dev CA/CN=Dev CA" \
  -out ca.pem

echo "Generando clave del servidor (cert.key) y CSR..."
openssl genrsa -out cert.key 2048
openssl req -new -key cert.key -subj "/C=US/ST=Local/L=Local/O=Dev Server/CN=localhost" -out server.csr

cat >v3ext.cnf <<EOF
subjectAltName = DNS:localhost, IP:127.0.0.1
EOF

echo "Firmando CSR con la CA para generar cert.crt (incluye SAN)..."
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial -out cert.crt -days 365 -sha256 -extfile v3ext.cnf

echo "Creando mongo.pem (clave privada + certificado) para MongoDB..."
cat cert.key cert.crt > mongo.pem

echo "Limpiando archivos temporales..."
rm -f server.csr v3ext.cnf ca.srl

echo "Ajustando permisos: claves privadas 600, públicos 644..."
chmod 600 ca.key cert.key mongo.pem
chmod 644 ca.pem cert.crt

echo "Generación completada. Archivos creados en: $WORKDIR"
echo "- ca.pem, ca.key (CA)"
echo "- cert.crt, cert.key (servidor)"
echo "- mongo.pem (cert+key para MongoDB)"

exit 0
