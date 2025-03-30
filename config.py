"""
Configuratie instellingen voor de Radiologger applicatie.
Dit bestand gebruikt omgevingsvariabelen voor productie instellingen.
"""

import os
from datetime import timedelta

class Config:
    """Basis configuratie instellingen"""
    # Flask instellingen
    SECRET_KEY = os.environ.get('FLASK_SECRET_KEY', 'development-key-replace-in-production')
    SESSION_TYPE = 'filesystem'
    PERMANENT_SESSION_LIFETIME = timedelta(days=7)
    
    # Database instellingen
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL', 'sqlite:///radiologger.db')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    
    # Logging instellingen
    LOG_DIR = os.environ.get('LOGS_DIR', 'logs')
    
    # Opname instellingen
    RECORDINGS_DIR = os.environ.get('RECORDINGS_DIR', 'recordings')
    RETENTION_DAYS = int(os.environ.get('RETENTION_DAYS', 30))
    LOCAL_FILE_RETENTION = int(os.environ.get('LOCAL_FILE_RETENTION', 0))  # Uren voordat lokale bestanden worden verwijderd (0 = direct na upload)
    
    # Wasabi S3 instellingen
    WASABI_ACCESS_KEY = os.environ.get('WASABI_ACCESS_KEY')
    WASABI_SECRET_KEY = os.environ.get('WASABI_SECRET_KEY')
    WASABI_BUCKET = os.environ.get('WASABI_BUCKET')
    WASABI_REGION = os.environ.get('WASABI_REGION', 'eu-central-1')
    WASABI_ENDPOINT_URL = os.environ.get('WASABI_ENDPOINT_URL', 'https://s3.eu-central-1.wasabisys.com')
    
    # Compatibiliteit met code dat S3_ prefix gebruikt
    S3_ENDPOINT = WASABI_ENDPOINT_URL
    S3_REGION = WASABI_REGION
    S3_BUCKET = WASABI_BUCKET
    S3_ACCESS_KEY = WASABI_ACCESS_KEY
    S3_SECRET_KEY = WASABI_SECRET_KEY
    
    # Systeem instellingen
    FFMPEG_PATH = os.environ.get('FFMPEG_PATH', '/usr/bin/ffmpeg')
    
    # Omroep Land van Cuijk instellingen
    OMROEP_LVC_URL = os.environ.get('OMROEP_LVC_URL', 'https://gemist.omroeplvc.nl/')
    
    # Dennis API instellingen
    DENNIS_API_URL = os.environ.get('DENNIS_API_URL', 'https://logger.dennishoogeveenmedia.nl/api/stations.json')
    
    # Zorg ervoor dat mappen bestaan
    @staticmethod
    def init_app(app):
        """Initialiseer app configuratie"""
        # Zorg ervoor dat de benodigde mappen bestaan
        os.makedirs(Config.LOG_DIR, exist_ok=True)
        os.makedirs(Config.RECORDINGS_DIR, exist_ok=True)
        
        # Submap voor elk station aanmaken
        stations_dir = os.path.join(Config.RECORDINGS_DIR, 'stations')
        os.makedirs(stations_dir, exist_ok=True)
        
        # Submap voor Dennis stations
        dennis_dir = os.path.join(Config.RECORDINGS_DIR, 'dennis')
        os.makedirs(dennis_dir, exist_ok=True)
        
        # Submap voor Omroep Land van Cuijk
        lvc_dir = os.path.join(Config.RECORDINGS_DIR, 'omroep land van cuijk')
        os.makedirs(lvc_dir, exist_ok=True)
        
        return app

class DevelopmentConfig(Config):
    """Ontwikkel configuratie"""
    DEBUG = True

class TestingConfig(Config):
    """Test configuratie"""
    TESTING = True
    SQLALCHEMY_DATABASE_URI = 'sqlite:///test.db'
    WTF_CSRF_ENABLED = False

class ProductionConfig(Config):
    """Productie configuratie"""
    DEBUG = False
    TESTING = False
    # In productie wordt de database URI in een omgevingsvariabele gezet
    # Voer database migraties uit voordat je deze wijzigt

# Configuratie object op basis van omgeving selecteren
config_env = os.environ.get('FLASK_ENV', 'development')
config = {
    'development': DevelopmentConfig,
    'testing': TestingConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig
}

# Standaard configuratie
app_config = config.get(config_env, config['default'])