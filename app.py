import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_wtf.csrf import CSRFProtect
from sqlalchemy.orm import DeclarativeBase
from apscheduler.schedulers.background import BackgroundScheduler
from flask_migrate import Migrate
from dotenv import load_dotenv
import logging

# Laad .env bestand als het bestaat
load_dotenv()

# Configuratie logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create base for SQLAlchemy models
class Base(DeclarativeBase):
    pass

# Initialize extensions
db = SQLAlchemy(model_class=Base)
login_manager = LoginManager()
csrf = CSRFProtect()
scheduler = BackgroundScheduler()
migrate = Migrate()

# Create and configure the app
app = Flask(__name__)

# Database configuratie uit omgevingsvariabelen
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
    'pool_pre_ping': True,  # Controleert de verbinding vóór gebruik
    'pool_recycle': 300,    # Recyclet verbindingen na 5 minuten
    'pool_timeout': 30,     # Timeout na 30 seconden
    'pool_size': 10,        # Maximum aantal connecties in de pool
    'max_overflow': 5       # Extra verbindingen boven pool_size (totaal 15)
}
# Recordings en logs
app.config['RECORDINGS_DIR'] = os.environ.get('RECORDINGS_DIR', 'recordings')
app.config['LOGS_DIR'] = os.environ.get('LOGS_DIR', 'logs')
app.config['RETENTION_DAYS'] = int(os.environ.get('RETENTION_DAYS', 30))
# Omroep LvC configuratie
app.config['OMROEP_LVC_URL'] = os.environ.get('OMROEP_LVC_URL', 'https://gemist.omroeplvc.nl/')
# FFmpeg pad
app.config['FFMPEG_PATH'] = os.environ.get('FFMPEG_PATH', 'ffmpeg')

# Zorg dat de benodigde mappen bestaan
os.makedirs(app.config['RECORDINGS_DIR'], exist_ok=True)
os.makedirs(app.config['LOGS_DIR'], exist_ok=True)

# Secret key
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "radiologger_secret_key")

logger.info(f"App configuratie geladen. Database: {app.config['SQLALCHEMY_DATABASE_URI']}")

# Initialize extensions with app
db.init_app(app)
migrate.init_app(app, db)
login_manager.init_app(app)
csrf.init_app(app)

# Set up database connection error handling
@app.teardown_request
def teardown_request(exception=None):
    if exception:
        db.session.rollback()
    db.session.remove()

# Configure login
login_manager.login_view = 'login'
login_manager.login_message = 'Please log in to access this page.'

# Import and register blueprints
from auth import auth_bp
from player import player_bp
from station_manager import station_bp
from api_integrations import api_bp

app.register_blueprint(auth_bp)
app.register_blueprint(player_bp)
app.register_blueprint(station_bp)
app.register_blueprint(api_bp)

# Import views
import models
from logger import start_scheduler

# Initialize the database
with app.app_context():
    db.create_all()

# Start the background scheduler
start_scheduler(scheduler)
scheduler.start()

# Import routes after everything else to avoid circular imports
from routes import *
