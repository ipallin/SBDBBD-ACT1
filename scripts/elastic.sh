# Elasticsearch abierto
curl http://localhost:9200/_cat/indices?v
curl "http://localhost:9200/articulos/_search?q=*"
curl -XDELETE http://localhost:9200/articulos  # ¡solo dataset de prueba!
