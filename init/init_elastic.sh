#!/usr/bin/env bash
# init_elastic.sh
# Inicializa un índice "articulos" con algunos documentos de prueba.
#
# IMPORTANT: This script assumes Elasticsearch requires authentication (recommended).
# - Use it from inside the Docker network (e.g. run from another container) or
#   run with `docker run --network <compose-network> ...` so the hostname
#   `elasticsearch` resolves. Do NOT run this against an exposed unauthenticated
#   HTTP endpoint on the host.

set -euo pipefail

# Use the internal Docker Compose service hostname by default. Esto evita que
# el script haga llamadas a `localhost:9200` desde el host sin autenticación.
# Si más adelante habilitas TLS, cambia el esquema a https y monta los certificados.
ES_URL=${ES_URL:-http://elasticsearch:9200}

# Credenciales para autenticación básica si ES tiene seguridad activada.
# Por seguridad, evita usar el superusuario `elastic` desde la aplicación.
# En su lugar crea un usuario con permisos limitados (rol específico para índices).
ES_USER=${ES_USER:-elastic}
ES_PASS=${ES_PASS:-${ELASTIC_PASSWORD:-}}

auth_args=()
# Si se ha proporcionado contraseña, añadimos los argumentos de `curl` para
# autenticación básica. Esto hace que todas las llamadas a ES usen credenciales
# y previene ejecuciones anónimas accidentales.
if [ -n "${ES_PASS}" ]; then
  auth_args+=( -u "${ES_USER}:${ES_PASS}" )
fi

echo "[*] Creando índice 'articulos' en ${ES_URL} ..."
# Todas las llamadas `curl` usan `auth_args` cuando están disponibles: así
# el script funcionará tanto en entornos protegidos (con ELASTIC_PASSWORD)
# como en entornos de prueba donde no hay auth (aunque no es recomendable exponerlos).

curl "${auth_args[@]}" -s -S -X PUT "${ES_URL}/articulos" -H 'Content-Type: application/json' -d '{
  "mappings": {
    "properties": {
      "nombre":    { "type": "text" },
      "categoria": { "type": "keyword" },
      "precio":    { "type": "float" }
    }
  }
}'

echo
echo "[*] Insertando documentos de ejemplo..."

curl "${auth_args[@]}" -s -S -X POST "${ES_URL}/articulos/_doc" -H 'Content-Type: application/json' -d '{
  "nombre": "Teclado mecánico",
  "categoria": "perifericos",
  "precio": 59.99
}'

curl "${auth_args[@]}" -s -S -X POST "${ES_URL}/articulos/_doc" -H 'Content-Type: application/json' -d '{
  "nombre": "Ratón gaming",
  "categoria": "perifericos",
  "precio": 39.90
}'

curl "${auth_args[@]}" -s -S -X POST "${ES_URL}/articulos/_doc" -H 'Content-Type: application/json' -d '{
  "nombre": "Monitor 24 pulgadas",
  "categoria": "monitores",
  "precio": 129.00
}'

echo
echo "[*] Refrescando índice..."
curl "${auth_args[@]}" -s -S -X POST "${ES_URL}/articulos/_refresh"

echo
echo "[*] Estado final de /_cat/indices:"
curl "${auth_args[@]}" -s -S "${ES_URL}/_cat/indices?v"
echo
