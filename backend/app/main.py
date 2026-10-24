from fastapi import FastAPI

app = FastAPI(
    title="Quran Academy API",
    version="1.0.0"
)

@app.get("/")
def home():
    return {
        "message": "Welcome to Quran Academy API",
        "status": "running"
    }

@app.get("/health")
def health():
    return {
        "status": "healthy",
        "service": "Quran Academy Backend"
    }


@app.get("/health/db")
async def database_health():
    from fastapi import HTTPException
    from app.db.database import check_database

    try:
        connected = await check_database()
        return {
            "database": "PostgreSQL",
            "connected": connected,
            "status": "healthy"
        }
    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Database connection unavailable"
        )
