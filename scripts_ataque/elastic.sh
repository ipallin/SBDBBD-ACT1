#!/usr/bin/env bash
set -euo pipefail
# Elasticsearch abierto
curl http://localhost:9200/_cat/indices
curl "http://localhost:9200/articulos/_search?q=*"
curl -XDELETE http://localhost:9200/articulos 

# Elasticsearch protegido con autenticación básica
curl -sS -G "http://10.200.70.206:8000/articulos" --data-urlencode "q=teclado" --data "size=10" -u "app_user:ReplaceWithAppUs3rPass!" -i
