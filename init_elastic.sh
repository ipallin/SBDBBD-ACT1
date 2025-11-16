#!/usr/bin/env bash
# init_elastic.sh
# Crea un índice de ejemplo y datos base en Elasticsearch para pruebas.
# Uso:
#   ES_HOST=localhost ES_PORT=9200 ./init_elastic.sh
#   Si Elasticsearch tiene autenticación básica:
#   ES_USER=elastic ES_PASS=changeme ./init_elastic.sh

set -euo pipefail

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_USER="${ES_USER:-}"
ES_PASS="${ES_PASS:-}"
ES_URL="http://${ES_HOST}:${ES_PORT}"
INDEX="sample-index"

# Construir opción de autenticación si se proporcionó usuario
AUTH_OPTS=()
if [[ -n "${ES_USER}" ]]; then
    AUTH_OPTS+=("-u" "${ES_USER}:${ES_PASS}")
fi

echo "Esperando a que Elasticsearch esté disponible en ${ES_URL}..."
# Esperar hasta que el servicio responda (200) o (401 si está protegido)
until status=$(curl -sS "${AUTH_OPTS[@]}" -o /dev/null -w "%{http_code}" "${ES_URL}") && { [[ "$status" == "200" ]] || [[ "$status" == "401" ]]; }; do
    printf '.'
    sleep 1
done
echo
echo "Elasticsearch respondio con status ${status}."

# Comprobar si el índice ya existe
if curl -sS "${AUTH_OPTS[@]}" -o /dev/null -w "%{http_code}" "${ES_URL}/${INDEX}" | grep -q '^200$'; then
    echo "Índice '${INDEX}' ya existe. Saliendo (no se re-creará)."
    exit 0
fi

echo "Creando índice '${INDEX}' con mapping de ejemplo..."
curl -sS "${AUTH_OPTS[@]}" -X PUT "${ES_URL}/${INDEX}" -H 'Content-Type: application/json' -d '{
    "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0
    },
    "mappings": {
        "properties": {
            "title":    { "type": "text", "fields": { "keyword": { "type": "keyword" } } },
            "content":  { "type": "text" },
            "date":     { "type": "date" },
            "tags":     { "type": "keyword" },
            "views":    { "type": "integer" }
        }
    }
}' >/dev/null

echo "Insertando documentos de ejemplo (bulk)..."
cat <<'NDJSON' | curl -sS "${AUTH_OPTS[@]}" -X POST "${ES_URL}/_bulk?refresh=wait_for" -H 'Content-Type: application/x-ndjson' --data-binary @-
{ "index": { "_index": "sample-index", "_id": "1" } }
{ "title": "Primera entrada", "content": "Documento de prueba número uno.", "date": "2023-01-10T12:00:00Z", "tags": ["prueba","inicio"], "views": 10 }
{ "index": { "_index": "sample-index", "_id": "2" } }
{ "title": "Segunda entrada", "content": "Más contenido de ejemplo.", "date": "2023-02-15T08:30:00Z", "tags": ["ejemplo"], "views": 25 }
{ "index": { "_index": "sample-index", "_id": "3" } }
{ "title": "Tercera entrada", "content": "Documentación y datos de prueba.", "date": "2023-03-20T16:45:00Z", "tags": ["prueba","docs"], "views": 5 }
{ "index": { "_index": "sample-index", "_id": "4" } }
{ "title": "Entrada con tags", "content": "Busqueda por tags.", "date": "2023-04-01T10:00:00Z", "tags": ["tags","busqueda"], "views": 7 }
{ "index": { "_index": "sample-index", "_id": "5" } }
{ "title": "Última entrada", "content": "Último ejemplo para pruebas.", "date": "2023-05-05T09:15:00Z", "tags": ["final"], "views": 3 }
NDJSON

echo "Verificando número de documentos en '${INDEX}'..."
count=$(curl -sS "${AUTH_OPTS[@]}" "${ES_URL}/${INDEX}/_count" | sed -n 's/.*"count":\([0-9]*\).*/\1/p' || true)
echo "Documentos en ${INDEX}: ${count:-desconocido}"

echo "Listo. Índice '${INDEX}' creado con datos de ejemplo."