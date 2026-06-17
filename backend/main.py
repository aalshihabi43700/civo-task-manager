from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def root():
    return {"message": "Backend is running on Kubernetes"}

@app.get("/health")
def health():
    return {"status": "ok"}

@app.get("/ready")
def ready():
    return {"status": "ready"}

@app.get("/config")
def config():
    return {
        "env": os.getenv("APP_ENV"),
        "db_host": os.getenv("DB_HOST")
    }