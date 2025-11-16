db = db.getSiblingDB('tienda');

db.usuarios.insertMany([
  { username: "alice", password: "alice123", role: "user" },
  { username: "bob",   password: "bob123",   role: "user" },
  { username: "admin", password: "admin123", role: "admin" }
]);

db.pedidos.insertMany([
  { user: "alice", producto: "ratón",   cantidad: 1, precio: 20 },
  { user: "alice", producto: "teclado", cantidad: 1, precio: 50 },
  { user: "bob",   producto: "monitor", cantidad: 2, precio: 200 }
]);
