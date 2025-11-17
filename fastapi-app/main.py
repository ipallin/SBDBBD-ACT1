from fastapi import FastAPI, HTTPException, Query, Depends, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel, validator, root_validator
from pymongo import MongoClient
import os
import requests

app = FastAPI(title="API NoSQL (segura)")
# -----------------------------
# MongoDB (conexión y configuración)
# - Variables y cliente que usan la API para operaciones de datos (usuarios, pedidos)
# -----------------------------
MONGO_HOST = os.getenv("MONGO_HOST", "mongo")
MONGO_DB = os.getenv("MONGO_DATABASE", "tienda")
# Credenciales sensibles: forzar su lectura desde el entorno (.env). No usar
# valores por defecto inseguros; fallamos al arrancar si faltan.
MONGO_USER = os.getenv("MONGO_USER")
MONGO_PASS = os.getenv("MONGO_PASS")
ELASTIC_HOST = os.getenv("ELASTIC_HOST", "elasticsearch")

# -----------------------------
# Elasticsearch (búsquedas)
# - Credenciales y host usados exclusivamente para consultas a ES desde la API
# - No usar el superuser `elastic` desde la aplicación; usar un usuario con
#   permisos limitados (ej. índice `articulos` read/write).
# -----------------------------
# Credenciales de aplicación para Elasticsearch (no usar el superuser `elastic`)
ELASTIC_APP_USER = os.getenv("ELASTIC_APP_USER")
ELASTIC_APP_PASS = os.getenv("ELASTIC_APP_PASS")

# API authentication: prefer explicit API credentials, fall back to elastic app creds
API_USER = os.getenv("API_USER")
API_PASS = os.getenv("API_PASS")

# HTTP Basic security dependency for endpoints that must be protected
security = HTTPBasic()

import secrets

def verify_api_credentials(credentials: HTTPBasicCredentials = Depends(security)):
    """Verifica credenciales HTTP Basic contra variables de entorno.
    - Usa `API_USER`/`API_PASS` si están definidas; si no, usa
      `ELASTIC_APP_USER`/`ELASTIC_APP_PASS`.
    Lanza `HTTPException(401)` con el header `WWW-Authenticate` si no coinciden.
    """
    expected_user = API_USER or ELASTIC_APP_USER
    expected_pass = API_PASS or ELASTIC_APP_PASS
    if not expected_user or not expected_pass:
        raise HTTPException(status_code=500, detail="API credentials not configured on server")

    # Comparación segura en tiempo constante
    valid_user = secrets.compare_digest(credentials.username, expected_user)
    valid_pass = secrets.compare_digest(credentials.password, expected_pass)
    if not (valid_user and valid_pass):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

# Validar presencia de variables sensibles en tiempo de arranque para evitar
# comportamientos inseguros por usar credenciales por defecto.
missing = [k for k, v in {
    "MONGO_USER": MONGO_USER,
    "MONGO_PASS": MONGO_PASS,
    "ELASTIC_APP_USER": ELASTIC_APP_USER,
    "ELASTIC_APP_PASS": ELASTIC_APP_PASS,
}.items() if not v]
if missing:
    raise RuntimeError(f"Faltan variables de entorno sensibles: {', '.join(missing)}.\nPlease set them in .env before starting the app.")

mongo = MongoClient(
    host=MONGO_HOST,
    username=MONGO_USER,
    password=MONGO_PASS,
    authSource=MONGO_DB,
)
db = mongo[MONGO_DB]


def validate_no_operators_recursive(data: dict):
    """Validación recursiva para estructuras anidadas.
    - Claves que empiezan por '$'
    - Valores string que empiezan por '$' o contienen '$'
    - Dicts anidados se procesan recursivamente
    Diseñado para usarse desde validadores raíz de Pydantic.
    Lanza `ValueError` para integrarse con la validación de Pydantic.
    """
    for k, v in data.items():
        if isinstance(k, str) and k.startswith("$"):
            raise ValueError("Clave con operador Mongo")
        if isinstance(v, dict):
            validate_no_operators_recursive(v)
        elif isinstance(v, str) and v.strip().startswith("$"):
            raise ValueError("Valor con operador Mongo")
        elif isinstance(v, str) and "$" in v:
            raise ValueError("Caracter '$' bloqueado")


class Login(BaseModel):
    username: str
    password: str

    @root_validator(pre=True)
    def check_no_operators(cls, values):
        # Validación centralizada para bloquear operadores Mongo en cualquier parte del payload
        validate_no_operators_recursive(values)
        return values


class Pedido(BaseModel):
    producto: str
    cantidad: int
    usuario: str

    @root_validator(pre=True)
    def check_no_operators(cls, values):
        # Validación centralizada para bloquear operadores Mongo en cualquier parte del payload
        validate_no_operators_recursive(values)
        return values

    @validator("cantidad")
    def cantidad_positiva(cls, v):
        # Evita inserciones con cantidad <= 0
        if v <= 0:
            raise ValueError("La cantidad debe ser positiva")
        return v


def validate_no_operators(data: dict):
    """Validación recursiva para estructuras anidadas.
    - Claves que empiezan por '$'
    - Valores string que empiezan por '$' o contienen '$'
    - Dicts anidados se procesan recursivamente
    Se usa antes de insertar datos en Mongo para evitar inyección de operadores.
    """
    for k, v in data.items():
        if isinstance(k, str) and k.startswith("$"):
            raise HTTPException(status_code=400, detail="Clave con operador Mongo")
        if isinstance(v, dict):
            validate_no_operators(v)
        elif isinstance(v, str) and v.strip().startswith("$"):
            raise HTTPException(status_code=400, detail="Valor con operador Mongo")
        elif isinstance(v, str) and "$" in v:
            raise HTTPException(status_code=400, detail="Caracter '$' bloqueado")


def escape_es_query(q: str) -> str:
    """Escapa caracteres reservados de la sintaxis de query string de Elasticsearch.
    Minimiza el riesgo de expansiones inesperadas / wildcard injection.
    """
    reserved = ['+', '-', '!', '(', ')', '{', '}', '[', ']', '^', '"', '~', '*', '?', ':', '\\', '/']
    escaped = []
    for ch in q:
        if ch in reserved:
            escaped.append(f"\\{ch}")
        else:
            escaped.append(ch)
    return "".join(escaped)


# -----------------------------
# Endpoints que usan MongoDB
# - `/login_mongo`, `/pedidos`, etc. leen/escriben datos en la base Mongo
# -----------------------------


@app.get("/health")
def health():
    return {"status": "ok", "mode": "secure"}


@app.post("/login_mongo")
def login(data: Login):
    # Ahora usamos Login (Pydantic) → bloquea payloads con operadores $ maliciosos
    user = db.usuarios.find_one(
        {"username": data.username, "password": data.password},
        {"_id": 0},
    )
    if user:
        return {"msg": "ok", "user": user.get("username")}
    raise HTTPException(status_code=401, detail="Bad creds")


@app.get("/pedidos")
def listar_pedidos(page: int = Query(1, ge=1), size: int = Query(50, ge=1, le=200)):
    # evita devolver listas masivas y facilita control de uso
    skip = (page - 1) * size
    cursor = db.pedidos.find({}, {"_id": 0}).skip(skip).limit(size)
    pedidos = list(cursor)
    total = db.pedidos.count_documents({})
    return {"page": page, "size": size, "total": total, "pedidos": pedidos}


@app.post("/pedidos")
def crear_pedido(pedido: Pedido):
    # El modelo Pedido ya valida recursivamente 
    payload = pedido.dict()
    db.pedidos.insert_one(payload)
    return {"msg": "pedido_creado"}


# -----------------------------
# Endpoint que usa Elasticsearch
# - `/articulos` delega la búsqueda en Elasticsearch y por tanto utiliza
#   las credenciales `ELASTIC_APP_USER`/`ELASTIC_APP_PASS` para autenticarse.
# - La API actúa como proxy seguro y aplica validaciones/escapes antes de
#   pasar la consulta a ES.
# -----------------------------


@app.get("/articulos")
def art_search(
    q: str = Query(
        "",
        description="Texto a buscar. No se permiten wildcards globales ni q='*'.",
    ),
    page: int = Query(1, ge=1),
    size: int = Query(10, ge=1, le=50),
):
    # prohibir '*' o vacío para evitar escaneos
    if q.strip() == "*" or q.strip() == "":
        raise HTTPException(status_code=422, detail="Búsqueda demasiado amplia")

    # bloqueo de patrones basicos
    forbidden = ["..", "<", ">", ";"]
    if any(f in q for f in forbidden):
        raise HTTPException(status_code=422, detail="Patrón de búsqueda no permitido")

    # escape de caracteres reservados
    sanitized = escape_es_query(q)
    url = f"http://{ELASTIC_HOST}:9200/articulos/_search"
    params = {"q": sanitized, "size": size, "from": (page - 1) * size}
    auth = (ELASTIC_APP_USER, ELASTIC_APP_PASS)
    try:
        # Usamos autenticación HTTP Basic con el usuario de aplicación.
        resp = requests.get(url, params=params, timeout=3, auth=auth)
        if resp.status_code in (401, 403):
            raise HTTPException(status_code=resp.status_code, detail="No autorizado")
        data = resp.json()
        # Metadatos de paginación devueltos
        data["page"] = page
        data["size"] = size
        return data
    except requests.exceptions.Timeout:
        raise HTTPException(status_code=504, detail="Timeout consultando ES")
    except requests.exceptions.ConnectionError:
        raise HTTPException(status_code=502, detail="No se puede contactar con ES desde la API")
