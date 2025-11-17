#!/usr/bin/env bash
# init_elastic.sh
# Inicializa un índice "articulos" con algunos documentos de prueba

ES_URL=${ES_URL:-http://localhost:9200}

echo "[*] Creando índice 'articulos' en ${ES_URL} ..."

curl -X PUT "${ES_URL}/articulos" -H 'Content-Type: application/json' -d '{
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

curl -X POST "${ES_URL}/articulos/_doc" -H 'Content-Type: application/json' -d '{
  "nombre": "Teclado mecánico",
  "categoria": "perifericos",
  "precio": 59.99
}'

curl -X POST "${ES_URL}/articulos/_doc" -H 'Content-Type: application/json' -d '{
  "nombre": "Ratón gaming",
  "categoria": "perifericos",
  "precio": 39.90
}'

curl -X POST "${ES_URL}/articulos/_doc" -H 'Content-Type: application/json' -d '{
  "nombre": "Monitor 24 pulgadas",
  "categoria": "monitores",
  "precio": 129.00
}'

echo
echo "[*] Refrescando índice..."
curl -X POST "${ES_URL}/articulos/_refresh"

echo
echo "[*] Estado final de /_cat/indices:"
curl "${ES_URL}/_cat/indices?v"
echo
