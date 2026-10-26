import os
from app.db.database import env
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import router

app = FastAPI(title="Quran Academy API", version="1.0.0")


@app.get("/")
def home():
    return {"message": "Welcome to Quran Academy API", "status": "running"}


@app.get("/health")
def health():
    return {"status": "healthy", "service": "Quran Academy Backend"}


@app.get("/health/db")
async def database_health():
    from fastapi import HTTPException
    from app.db.database import check_database

    try:
        connected = await check_database()
        return {"database": "PostgreSQL", "connected": connected, "status": "healthy"}
    except Exception:
        raise HTTPException(status_code=503, detail="Database connection unavailable")


# Exact origins only. The public Pages demo does not require API access.
origins = [
    o.strip()
    for o in os.environ.get("ACADEMY_ORIGINS", env.get("ACADEMY_ORIGINS", "")).split(
        ","
    )
    if o.strip()
]
if origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=origins,
        allow_methods=["GET", "POST", "PUT"],
        allow_headers=["Authorization", "Content-Type"],
    )
app.include_router(router)


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    if request.url.path.startswith("/api"):
        response.headers["Cache-Control"] = "no-store"
    return response


# Do not echo credential inputs back in validation errors.
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


@app.exception_handler(RequestValidationError)
async def validation_error(request, exc):
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Invalid input. Check field formats, lengths, and required values."
        },
    )
