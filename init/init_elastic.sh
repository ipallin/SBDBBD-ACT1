#!/usr/bin/env bash
set -euo pipefail

ES_URL=${ES_URL:-http://elasticsearch:9200}
ES_USER=${ES_USER:-elastic}
ES_PASS=${ES_PASS:-${ELASTIC_PASSWORD:-}}
auth_args=()
if [ -n "${ES_PASS}" ]; then
  auth_args+=( -u "${ES_USER}:${ES_PASS}" )
fi

echo "[*] Creando índice 'articulos' en ${ES_URL} ..."

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
