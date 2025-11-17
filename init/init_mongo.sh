#!/usr/bin/env bash
set -euo pipefail

# Único script de inicialización para Mongo: crea usuarios de autenticación

DB_NAME="${MONGO_INITDB_DATABASE:-tienda}"
APP_USER="${MONGO_APP_USER:-}"
APP_PASS="${MONGO_APP_PASS:-}"
RW_USER="${MONGO_RW_USER:-}"
RW_PASS="${MONGO_RW_PASS:-}"

echo "[init] Inicializando base de datos Mongo: $DB_NAME"

echo "[init] Variables detectadas: APP_USER=${APP_USER:+set}, RW_USER=${RW_USER:+set}"

# Ejecutamos comandos JS con mongosh

mongosh <<EOF
// Nos movemos a la base de datos de trabajo
var dbName = "$DB_NAME";
db = db.getSiblingDB(dbName);

// 1) Crear (o recrear) usuarios de autenticación para la BD (readWrite)
if ("$APP_USER" && "$APP_PASS") {
  try { db.dropUser("$APP_USER"); } catch (e) {}
  db.createUser({ user: "$APP_USER", pwd: "$APP_PASS", roles: [ { role: 'readWrite', db: dbName } ] });
  print('[init] Usuario de autenticación creado:', "$APP_USER");
}

if ("$RW_USER" && "$RW_PASS" && "$RW_USER" !== "$APP_USER") {
  try { db.dropUser("$RW_USER"); } catch (e) {}
  db.createUser({ user: "$RW_USER", pwd: "$RW_PASS", roles: [ { role: 'readWrite', db: dbName } ] });
  print('[init] Usuario de autenticación creado:', "$RW_USER");
}

// 2) Insertar/asegurar documentos de ejemplo en colecciones (datos de la app)
// Evitamos crear credenciales por defecto inseguras aquí; usamos solo datos de ejemplo.

// Limpiamos colecciones de ejemplo para determinismo en la inicialización.
db.usuarios.deleteMany({});
db.pedidos.deleteMany({});

// Usuarios de ejemplo (clientes)
db.usuarios.insertMany([
  { username: "alice", password: "alice123", role: "user" },
  { username: "bob", password: "bob123", role: "user" }
]);

// Si se definió MONGO_APP_USER, asegurar un documento que represente a la cuenta de la app
if ("$APP_USER" && "$APP_PASS") {
  db.usuarios.updateOne(
    { username: "$APP_USER" },
    { \$set: { username: "$APP_USER", password: "$APP_PASS", role: "app" } },
    { upsert: true }
  );
}

// Pedidos de ejemplo
db.pedidos.insertMany([
  { user: "alice", producto: "ratón",   cantidad: 1, precio: 20 },
  { user: "alice", producto: "teclado", cantidad: 1, precio: 50 },
  { user: "bob",   producto: "monitor", cantidad: 2, precio: 200 }
]);

print('[init] Documentos de ejemplo insertados.');

// Mostrar usuarios de autenticación y documentos insertados para verificación
try { printjson(db.getUsers()); } catch (e) { }
printjson(db.usuarios.find().toArray());
printjson(db.pedidos.find().toArray());
EOF

echo "[init] Inicialización de Mongo completada."
