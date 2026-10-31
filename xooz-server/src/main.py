from fastapi import FastAPI
from src.routes.audio import router as audio_router
from src.routes.digest import router as digest_router

app = FastAPI(
    title="Xooz API",
    description="Backend for Xooz — your AI conversation digest",
    version="1.0.0"
)

app.include_router(audio_router, prefix="/api/v1")
app.include_router(digest_router, prefix="/api/v1")

@app.get("/")
def root():
    return {"status": "Xooz backend is running"}