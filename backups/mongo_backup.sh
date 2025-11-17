#!/usr/bin/env bash
set -euo pipefail
# Script para realizar un backup de la base de datos MongoDB segura
docker exec mongo_seguro mongodump --db tienda --out /backup
docker cp mongo_seguro:/backup ./mongo-backup
echo "Backup de MongoDB completado y guardado en ./mongo-backup/"