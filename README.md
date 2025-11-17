# SBDBBD-ACT1

Plataforma de ejemplo para la asignatura **Seguridad en Bases de Datos, Blockchain y Big Data**. El proyecto despliega una pila segura con MongoDB + Elasticsearch + FastAPI protegidos con TLS, credenciales fuertes y datos de ejemplo listos para practicar.

## Estructura del proyecto

```
.
├── docker-compose.yaml         # Orquesta los servicios seguros
├── fastapi-app/                # API FastAPI (TLS, conexión a Mongo y ES)
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── init/
│   ├── init_mongo.sh           # Crea usuarios y datos de ejemplo en Mongo
│   └── init_elastic.sh         # Provisiona índice y documentos en Elasticsearch
├── certs/
│   ├── generate_certs.sh       # Script local para generar la CA y los PEM
│   ├── ca.pem / ca.key         # Autoridad certificadora usada internamente
│   ├── cert.crt / cert.key     # Certificado TLS de FastAPI
│   └── mongo.pem               # Certificado+clave para mongod
├── scripts_ataque/             # PoC y scripts de ataque para prácticas
│   ├── elastic.sh
│   └── sqli.sh
├── backups/                    # Carpeta para dumps/respaldos (vacía por defecto)
└── .inseguros_archivo/         # Versión insegura (solo referencia comparativa)
```

> Los certificados (`certs/*.pem/.crt/.key`) y el archivo `.env` **no deben subirse** al repositorio, ya que contienen secretos locales.

## Prerrequisitos

- Linux/macOS/WSL con Bash.
- Docker Engine ≥ 24 y complemento `docker compose`.
- OpenSSL (para regenerar certificados).
- (Opcional) `curl` y `jq` para probar la API.

## Configuración paso a paso

### 1. Clona el repositorio

```
git clone https://github.com/ipallin/SBDBBD-ACT1.git
cd SBDBBD-ACT1
```

### 2. Crea tu archivo `.env`

Rellena credenciales fuertes para todos los servicios. Como referencia:

```
MONGO_ROOT_USER=admin_seguro
MONGO_ROOT_PASS=changeme-superseguro
MONGO_APP_USER=api_rw
MONGO_APP_PASS=api_rw_password
MONGO_RW_USER=operaciones_rw
MONGO_RW_PASS=operaciones_password

ELASTIC_PASSWORD=contraseña_elastic
ELASTIC_APP_USER=fastapi_es
ELASTIC_APP_PASS=fastapi_es_password

API_USER=api_basic
API_PASS=api_basic_password
APP_MODE=secure
```

> Ajusta los valores según tus políticas. El archivo `.env` ya está en `.gitignore`.

### 3. Genera la CA y los certificados

```
cd certs
./generate_certs.sh
```

Este script crea `ca.pem/ca.key`, `cert.crt/cert.key` (FastAPI) y `mongo.pem` (usado por mongod) con permisos mínimos.

### 4. Levanta toda la pila

```
docker compose up --build -d
```

Componentes desplegados:
- `mongo_seguro`: MongoDB 7 con TLS obligatorio y usuarios iniciales definidos en `init/init_mongo.sh`.
- `es_seguro`: Elasticsearch 7 con seguridad nativa activada y datos de ejemplo (`init/init_elastic.sh`).
- `fastapi_seguro`: API FastAPI con TLS (cert.crt/cert.key) que consume Mongo y Elasticsearch mediante credenciales de aplicación.

### 5. Verifica el estado

```
docker compose ps
```

Comprueba también los logs individuales si necesitas depurar:

```
docker logs mongo_seguro -f
docker logs es_seguro -f
docker logs fastapi_seguro -f
```

### 6. Prueba la API sobre HTTPS

Usa la CA generada para validar el certificado autofirmado de FastAPI:

```
curl --cacert certs/ca.pem https://localhost:8000/health
```

Endpoints principales:
- `POST /login_mongo` → login contra Mongo (payload JSON con `username`/`password`).
- `GET /pedidos` → listado paginado.
- `POST /pedidos` → inserción de pedidos (valida operadores Mongo).
- `GET /articulos` → proxy seguro hacia Elasticsearch (requiere credenciales HTTP Basic configuradas en `.env`).

### 7. Acceder a Mongo/Elasticsearch manualmente

- Mongo dentro del contenedor (TLS + auth):
	```
	docker exec -it mongo_seguro mongosh --tls --tlsCAFile /mongo-certs/ca.pem -u "$MONGO_APP_USER" -p "$MONGO_APP_PASS" tienda
	```
- Elasticsearch (requiere `ELASTIC_PASSWORD`):
	```
	curl -k -u elastic:$ELASTIC_PASSWORD https://localhost:9200 -H 'Content-Type: application/json'
	```

### 8. Detener y limpiar

```
docker compose down
```

Añade `-v` si deseas borrar los volúmenes con los datos persistentes.

## Entorno inseguro (opcional)

El directorio `.inseguros_archivo/` almacena una versión deliberadamente insegura de la pila (sin TLS, usuarios débiles, etc.). Úsalo solo para comparar vulnerabilidades vs. la variante segura. No lo despliegues en entornos reales.

## Scripts de laboratorio

La carpeta `scripts_ataque/` contiene ejemplos de explotación (SQLi, ataques a Elasticsearch) usados en la asignatura. Ejecútalos únicamente en tu entorno de laboratorio tras levantar la variante insegura.

## Despliegue automático en OpenStack

Para aprovisionar una instancia en OpenStack con todo el stack levantado automáticamente, prepara un archivo `cloud-config.yaml` para `cloud-init` (ajusta las credenciales y dominios antes de lanzar la máquina):

```yaml
#cloud-config
package_update: true
package_upgrade: true
packages:
	- docker.io
	- docker-compose-plugin
	- git
	- openssl
write_files:
	- path: /home/ubuntu/.env_sbdbbd
		owner: ubuntu:ubuntu
		permissions: '0600'
		content: |
			# Sustituye estos valores por credenciales fuertes
			MONGO_ROOT_USER=admin_seguro
			MONGO_ROOT_PASS=changeme-superseguro
			MONGO_APP_USER=api_rw
			MONGO_APP_PASS=api_rw_password
			MONGO_RW_USER=operaciones_rw
			MONGO_RW_PASS=operaciones_password
			ELASTIC_PASSWORD=contraseña_elastic
			ELASTIC_APP_USER=fastapi_es
			ELASTIC_APP_PASS=fastapi_es_password
			API_USER=api_basic
			API_PASS=api_basic_password
			APP_MODE=secure
runcmd:
	- usermod -aG docker ubuntu
	- systemctl enable docker
	- systemctl start docker
	- sudo -u ubuntu git clone https://github.com/ipallin/SBDBBD-ACT1.git /home/ubuntu/SBDBBD-ACT1
	- sudo -u ubuntu install -m 600 /home/ubuntu/.env_sbdbbd /home/ubuntu/SBDBBD-ACT1/.env
	- sudo -u ubuntu bash -lc 'cd /home/ubuntu/SBDBBD-ACT1/certs && ./generate_certs.sh'
	- bash -lc 'cd /home/ubuntu/SBDBBD-ACT1 && docker compose up --build -d'
final_message: "SBDBBD-ACT1 desplegado. Revisa docker compose ps para validar el estado"
```
