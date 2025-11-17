#!/usr/bin/env bash
set -euo pipefail

# Crea usuarios de aplicación usando variables de entorno provistas por docker-compose
# Se ejecuta automáticamente por el entrypoint de Mongo al inicializar el contenedor

DB_NAME="${MONGO_INITDB_DATABASE:-tienda}"
APP_USER="${MONGO_APP_USER:-}"
APP_PASS="${MONGO_APP_PASS:-}"
RW_USER="${MONGO_RW_USER:-}"
RW_PASS="${MONGO_RW_PASS:-}"

echo "[init] Creando usuarios de aplicación en BD '$DB_NAME'..."

mongosh <<EOF
// Nos movemos a la base de datos de trabajo
var dbName = "$DB_NAME";
db = db.getSiblingDB(dbName);

// Usuario principal de la API (readWrite)
var appUser = "$APP_USER";
var appPass = "$APP_PASS";
if (appUser && appUser.length && appPass && appPass.length) {
  try { db.dropUser(appUser); } catch (e) {}
  db.createUser({
    user: appUser,
    pwd: appPass,
    roles: [ { role: 'readWrite', db: dbName } ]
  });
}

// Segundo usuario readWrite opcional (p.ej. para otras integraciones)
var rwUser = "$RW_USER";
var rwPass = "$RW_PASS";
if (rwUser && rwUser.length && rwPass && rwPass.length && rwUser !== appUser) {
  try { db.dropUser(rwUser); } catch (e) {}
  db.createUser({
    user: rwUser,
    pwd: rwPass,
    roles: [ { role: 'readWrite', db: dbName } ]
  });
}

printjson(db.getUsers());
EOF

echo "[init] Usuarios de aplicación creados (si estaban definidos)."
