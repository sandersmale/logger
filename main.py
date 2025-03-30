import os
import logging
from flask import Flask

# Configureer logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('app')

# create the app
app = Flask(__name__)

# setup a secret key
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "development-key-replace-in-production")

# configureer de database
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL")
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}

# Log de database URL (verberg wachtwoord voor veiligheid)
db_url = os.environ.get("DATABASE_URL", "")
if db_url:
    parts = db_url.split('@')
    if len(parts) > 1:
        credential_parts = parts[0].split(':')
        if len(credential_parts) > 2:
            masked_url = f"{credential_parts[0]}:****@{parts[1]}"
            logger.info(f"App configuratie geladen. Database: {masked_url}")

# Importeer app.py (de echte app definitie)
from app import app as flask_app

# Deze import moet na app.py komen om circulaire imports te voorkomen
import routes

# Alleen voor lokale ontwikkeling
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)