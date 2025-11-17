from fastapi import FastAPI, HTTPException, Query, Depends  # Se agregó Depends (reservado para futuras dependencias de seguridad)
from pydantic import BaseModel, validator
from pymongo import MongoClient
import os
import requests

app = FastAPI(title="API NoSQL (segura)")

MONGO_HOST = os.getenv("MONGO_HOST", "mongo")
MONGO_DB = os.getenv("MONGO_DATABASE", "tienda")
MONGO_USER = os.getenv("MONGO_USER", "api_user")
MONGO_PASS = os.getenv("MONGO_PASS", "api1234")
ELASTIC_HOST = os.getenv("ELASTIC_HOST", "elasticsearch")

mongo = MongoClient(
    host=MONGO_HOST,
    username=MONGO_USER,
    password=MONGO_PASS,
    authSource=MONGO_DB,
)
db = mongo[MONGO_DB]


class Login(BaseModel):
    username: str
    password: str

    @validator("*")
    def no_mongo_operators(cls, v):
        # Validador genérico sobre todos los campos: bloquea
        # 1) Cualquier dict (evita inyección de operadores complejos)
        # 2) Strings que comiencen por '$' (operadores Mongo como $ne, $gt, etc.)
        # 3) Presencia de '$' en cualquier parte del string (defensa mínima solicitada)
        if isinstance(v, dict):
            raise ValueError("Payload no permitido")
        if isinstance(v, str) and v.strip().startswith("$"):
            raise ValueError("Operadores no permitidos")
        if isinstance(v, str) and "$" in v:
            raise ValueError("Caracter '$' bloqueado")
        return v


class Pedido(BaseModel):
    producto: str
    cantidad: int
    usuario: str

    @validator("cantidad")
    def cantidad_positiva(cls, v):
        # Evita inserciones con cantidad <= 0
        if v <= 0:
            raise ValueError("La cantidad debe ser positiva")
        return v

    @validator("producto", "usuario")
    def no_mongo_operator_strings(cls, v):
        # Mismo patrón defensivo: bloquea aparición de '$' (operadores Mongo)
        if isinstance(v, str) and (v.strip().startswith("$") or "$" in v):
            raise ValueError("Operadores Mongo bloqueados")
        return v


def validate_no_operators(data: dict):
    """Validación recursiva para estructuras anidadas.
    Recorre cada clave/valor y bloquea:
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
    # Paginación añadida: evita devolver listas masivas y facilita control de uso.
    skip = (page - 1) * size
    cursor = db.pedidos.find({}, {"_id": 0}).skip(skip).limit(size)
    pedidos = list(cursor)
    total = db.pedidos.count_documents({})
    return {"page": page, "size": size, "total": total, "pedidos": pedidos}


@app.post("/pedidos")
def crear_pedido(pedido: Pedido):
    # Se valida recursivamente para prevenir claves tipo $set, $ne, etc. antes de insertar.
    payload = pedido.dict()
    validate_no_operators(payload)
    db.pedidos.insert_one(payload)
    return {"msg": "pedido_creado"}


@app.get("/articulos")
def art_search(
    q: str = Query(
        "",
        description="Texto a buscar. No se permiten wildcards globales ni q='*'.",
    ),
    page: int = Query(1, ge=1),
    size: int = Query(10, ge=1, le=50),
):
    # Defensa mínima: prohibir '*' o vacío para evitar escaneos masivos.
    if q.strip() == "*" or q.strip() == "":
        raise HTTPException(status_code=422, detail="Búsqueda demasiado amplia")

    # Bloqueo de patrones básicos potencialmente abusivos.
    forbidden = ["..", "<", ">", ";"]
    if any(f in q for f in forbidden):
        raise HTTPException(status_code=422, detail="Patrón de búsqueda no permitido")

    # Escape de caracteres reservados para evitar interpretaciones especiales.
    sanitized = escape_es_query(q)
    url = f"http://{ELASTIC_HOST}:9200/articulos/_search"
    params = {"q": sanitized, "size": size, "from": (page - 1) * size}
    try:
        resp = requests.get(url, params=params, timeout=3)
        if resp.status_code in (401, 403):
            raise HTTPException(status_code=resp.status_code, detail="No autorizado")
        data = resp.json()
        # Metadatos de paginación devueltos junto con la respuesta de ES.
        data["page"] = page
        data["size"] = size
        return data
    except requests.exceptions.Timeout:
        raise HTTPException(status_code=504, detail="Timeout consultando ES")
    except requests.exceptions.ConnectionError:
        raise HTTPException(status_code=502, detail="No se puede contactar con ES desde la API")
