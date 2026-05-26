import os
from pathlib import Path

from dotenv import load_dotenv


DOTENV_PATH = Path(__file__).resolve().parent / ".env"
load_dotenv(DOTENV_PATH, override=True)


class Config:
    SQLALCHEMY_DATABASE_URI = os.getenv(
        "DATABASE_URL",
        "postgresql+psycopg2://postgres:postgres@localhost:5432/zam_reminder",
    )
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
    GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-flash-lite-latest")
    FIREBASE_AUTH_REQUIRED = os.getenv("FIREBASE_AUTH_REQUIRED", "false").lower() == "true"
    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")
