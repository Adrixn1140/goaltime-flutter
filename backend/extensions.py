"""Instancias de las extensiones, creadas sin ligar a la app.

Se importan desde `app.py` (que las inicializa) y desde los blueprints y los tests,
para evitar imports circulares.
"""

from flask_cors import CORS
from flask_jwt_extended import JWTManager
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
jwt = JWTManager()
cors = CORS()
