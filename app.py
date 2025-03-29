import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_wtf.csrf import CSRFProtect
from sqlalchemy.orm import DeclarativeBase
from apscheduler.schedulers.background import BackgroundScheduler

# Create base for SQLAlchemy models
class Base(DeclarativeBase):
    pass

# Initialize extensions
db = SQLAlchemy(model_class=Base)
login_manager = LoginManager()
csrf = CSRFProtect()
scheduler = BackgroundScheduler()

# Create and configure the app
app = Flask(__name__)
app.config.from_pyfile('config.py')
app.secret_key = os.environ.get("SESSION_SECRET", "radiologger_secret_key")

# Initialize extensions with app
db.init_app(app)
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
