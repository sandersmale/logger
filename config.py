import os
import logging
from datetime import timedelta

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)

# Base directory
BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# Database
SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL', 'sqlite:///radiologger.db')
SQLALCHEMY_TRACK_MODIFICATIONS = False
SQLALCHEMY_ENGINE_OPTIONS = {
    "pool_recycle": 60,  # Reconnect after 60 seconds idle
    "pool_pre_ping": True,  # Check connection validity before each use
    "pool_size": 10,  # Maintain up to 10 connections
    "max_overflow": 15,  # Allow up to 15 extra connections
    "connect_args": {
        "connect_timeout": 10,  # 10 seconds connection timeout
        "keepalives": 1,  # Enable keepalives
        "keepalives_idle": 30,  # Idle time before sending keepalive
        "keepalives_interval": 10  # Interval between keepalives
    }
}

# Session configuration
SESSION_TYPE = 'filesystem'
PERMANENT_SESSION_LIFETIME = timedelta(days=7)  # 7 day session lifetime
SESSION_SECRET = os.environ.get("SESSION_SECRET", "radiologger_secret_key")

# File paths
RECORDINGS_DIR = os.path.join(BASE_DIR, 'recordings')
LOGS_DIR = os.path.join(BASE_DIR, 'logs')

# S3 Storage (Wasabi)
S3_BUCKET = os.environ.get('S3_BUCKET', 'radiologger')
S3_ENDPOINT = os.environ.get('S3_ENDPOINT', 'https://s3.eu-central-1.wasabisys.com')
S3_REGION = os.environ.get('S3_REGION', 'eu-central-1')

# External APIs
DENNIS_API_URL = os.environ.get('DENNIS_API_URL', 'https://logger.dennishoogeveenmedia.nl/audio/')
OMROEP_LVC_URL = os.environ.get('OMROEP_LVC_URL', 'https://gemist.omroeplvc.nl/')

# ffmpeg configuration
FFMPEG_PATH = os.environ.get('FFMPEG_PATH', 'ffmpeg')  # Use just the command name to find it in PATH

# File retention (in hours)
LOCAL_FILE_RETENTION = int(os.environ.get('LOCAL_FILE_RETENTION', '2'))  # 2 hours

# Ensure directories exist
os.makedirs(RECORDINGS_DIR, exist_ok=True)
os.makedirs(LOGS_DIR, exist_ok=True)
