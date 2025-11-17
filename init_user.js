// init_user.js
// Crea un usuario con rol limitado para que lo use la aplicación

db = db.getSiblingDB("tienda");

db.createUser({
  user: "api_user",
  pwd: "api1234",
  roles: [
    { role: "readWrite", db: "tienda" }
  ]
});
