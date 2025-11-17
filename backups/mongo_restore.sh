#!/usr/bin/env bash
set -euo pipefail
# Script para restaurar un backup en la base de datos MongoDB segura
docker exec mongo_seguro mongorestore /backup # Comando para restaurar desde el backup si es necesario
echo "Restauración de MongoDB completada desde /backup en el contenedor mongo_seguro."
