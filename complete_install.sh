#!/bin/bash
# Radiologger volledige installatiescript
# Dit script download en installeert alle benodigde bestanden voor de Radiologger applicatie
# en zorgt ervoor dat deze correct worden ingesteld en gestart

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Instellingen
INSTALL_DIR="/opt/radiologger"
REPO_URL="https://github.com/sandersmale/logger"
BACKUP_DIR="/opt/radiologger_backup_$(date +%Y%m%d_%H%M%S)"

echo "====== RADIOLOGGER VOLLEDIGE INSTALLATIE ======"
echo "Dit script zal een volledige installatie van Radiologger uitvoeren"
echo "Huidige bestanden worden geback-upt naar $BACKUP_DIR"
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Dit script moet als root worden uitgevoerd (gebruik sudo)${NC}"
   exit 1
fi

# 1. Backup maken van bestaande installatie (indien aanwezig)
echo "Stap 1: Backup maken van bestaande installatie..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Bestaande installatie gevonden, backup maken..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$INSTALL_DIR"/* "$BACKUP_DIR"
    echo -e "${GREEN}✅ Backup gemaakt naar $BACKUP_DIR${NC}"
else
    echo "Geen bestaande installatie gevonden, nieuwe installatie wordt uitgevoerd."
    mkdir -p "$INSTALL_DIR"
fi

# 2. Voorbereiden van systeem en installeren dependencies
echo ""
echo "Stap 2: Systeem voorbereiden en dependencies installeren..."
apt-get update
apt-get install -y python3 python3-venv python3-pip ffmpeg postgresql postgresql-contrib nginx git

# 3. Radiologger gebruiker aanmaken (indien niet bestaat)
echo ""
echo "Stap 3: Radiologger gebruiker aanmaken..."
if id "radiologger" &>/dev/null; then
    echo "Gebruiker radiologger bestaat al."
else
    useradd -m -s /bin/bash radiologger
    echo -e "${GREEN}✅ Gebruiker radiologger aangemaakt${NC}"
fi

# 4. Benodigde mappen aanmaken
echo ""
echo "Stap 4: Benodigde mappen aanmaken..."
mkdir -p /var/log/radiologger
mkdir -p /var/lib/radiologger/recordings
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger
chmod -R 755 /var/log/radiologger
chmod -R 755 /var/lib/radiologger
echo -e "${GREEN}✅ Mappen aangemaakt en rechten ingesteld${NC}"

# 5. Download en installeer de applicatie vanuit GitHub
echo ""
echo "Stap 5: Applicatie downloaden en installeren..."
cd /tmp
if [ -d "/tmp/radiologger_repo" ]; then
    rm -rf /tmp/radiologger_repo
fi
git clone "$REPO_URL" /tmp/radiologger_repo
cp -r /tmp/radiologger_repo/* "$INSTALL_DIR"
chown -R radiologger:radiologger "$INSTALL_DIR"
chmod -R 755 "$INSTALL_DIR"
echo -e "${GREEN}✅ Applicatie gedownload en gekopieerd naar $INSTALL_DIR${NC}"

# 6. Controleer en herstel kritieke bestanden
echo ""
echo "Stap 6: Kritieke bestanden controleren..."
kritieke_bestanden=("main.py" "app.py" "routes.py" "player.py" "models.py" "logger.py" "auth.py" "config.py" "storage.py")
missende_bestanden=()

for bestand in "${kritieke_bestanden[@]}"; do
    if [ ! -f "$INSTALL_DIR/$bestand" ]; then
        missende_bestanden+=("$bestand")
    fi
done

if [ ${#missende_bestanden[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️ De volgende kritieke bestanden ontbreken:${NC}"
    for missend in "${missende_bestanden[@]}"; do
        echo "   - $missend"
    done
    
    echo "Aanmaken van ontbrekende bestanden..."
    
    # Controleer en creëer player.py als deze ontbreekt
    if [[ " ${missende_bestanden[*]} " =~ " player.py " ]]; then
        echo "📝 player.py aanmaken..."
        cat > "$INSTALL_DIR/player.py" << 'EOL'
import os
import io
import subprocess
from flask import render_template, send_file, Response, request, redirect, url_for, abort
from datetime import datetime, date, timedelta
from app import app, db
from models import Recording, Station
import logging

logger = logging.getLogger(__name__)

@app.route('/list_recordings')
def list_recordings():
    """Hoofdpagina - toont lijst met opnames met uitklapbaar menu"""
    try:
        # Haal alle stations op, gesorteerd op display_order
        stations = Station.query.order_by(Station.display_order).all()
        recordings_by_date = {}
        
        # Bereken data van afgelopen 30 dagen
        today = date.today()
        dates = [(today - timedelta(days=i)) for i in range(30)]
        
        # Voor elke datum, haal opnames op
        for current_date in dates:
            date_str = current_date.strftime('%Y-%m-%d')
            recordings_for_date = Recording.query.filter(Recording.date == current_date).all()
            
            if recordings_for_date:
                recordings_by_date[date_str] = {}
                for recording in recordings_for_date:
                    station = Station.query.get(recording.station_id)
                    if station:
                        if station.name not in recordings_by_date[date_str]:
                            recordings_by_date[date_str][station.name] = []
                        recordings_by_date[date_str][station.name].append({
                            'id': recording.id,
                            'hour': recording.hour,
                            'filepath': recording.filepath,
                            's3_uploaded': recording.s3_uploaded
                        })
        
        return render_template('list_recordings.html', 
                               recordings_by_date=recordings_by_date,
                               stations=stations,
                               title="Opnames Overzicht")
    except Exception as e:
        logger.error(f"Fout bij ophalen opnames: {str(e)}")
        return render_template('error.html', 
                               message=f"Er is een fout opgetreden bij het ophalen van de opnames: {str(e)}",
                               title="Fout")

@app.route('/player/<int:recording_id>')
def player(recording_id):
    """Audio player for recordings"""
    try:
        # Haal opname op basis van ID
        recording = Recording.query.get_or_404(recording_id)
        station = Station.query.get(recording.station_id)
        
        # Formatteer datum
        recording_date = recording.date.strftime('%Y-%m-%d')
        
        # Bepaal of bestand nog op server staat of alleen in S3
        local_file_exists = os.path.exists(recording.filepath)
        
        return render_template('player.html',
                               recording=recording,
                               station=station,
                               recording_date=recording_date,
                               local_file_exists=local_file_exists,
                               title=f"Player - {station.name} {recording_date} {recording.hour}:00")
    except Exception as e:
        logger.error(f"Fout bij laden player: {str(e)}")
        return render_template('error.html', 
                               message=f"Er is een fout opgetreden bij het laden van de player: {str(e)}",
                               title="Fout")

@app.route('/audio/fragment/<int:recording_id>')
def stream_audio_fragment(recording_id):
    """Stream a fragment of audio using ffmpeg"""
    try:
        # Haal opname op
        recording = Recording.query.get_or_404(recording_id)
        
        # Haal parameters uit query string
        start_time = request.args.get('start', '0')
        duration = request.args.get('duration', '60')
        
        # Bepaal bestandsnaam
        station = Station.query.get(recording.station_id)
        filename = f"{station.name}_{recording.date}_{recording.hour}.mp3"
        
        # Controleer of bestand lokaal bestaat
        if os.path.exists(recording.filepath):
            # Gebruik ffmpeg om fragment te extraheren
            cmd = [
                'ffmpeg',
                '-ss', start_time,
                '-t', duration,
                '-i', recording.filepath,
                '-f', 'mp3',
                '-acodec', 'libmp3lame',
                '-'
            ]
            
            def generate():
                process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                # Stuur data door naar client
                while True:
                    data = process.stdout.read(1024)
                    if not data:
                        break
                    yield data
                    
            return Response(generate(), mimetype='audio/mpeg')
        else:
            # TODO: Haal bestand op uit S3 als lokaal niet beschikbaar
            abort(404, description="Audio bestand niet lokaal beschikbaar")
    except Exception as e:
        logger.error(f"Fout bij streamen audio fragment: {str(e)}")
        abort(500, description=f"Error: {str(e)}")

@app.route('/audio/download/<int:recording_id>')
def stream_full_audio(recording_id):
    """Stream the full audio file for download"""
    try:
        # Haal opname op
        recording = Recording.query.get_or_404(recording_id)
        
        # Bepaal bestandsnaam
        station = Station.query.get(recording.station_id)
        filename = f"{station.name}_{recording.date}_{recording.hour}.mp3"
        
        # Controleer of bestand lokaal bestaat
        if os.path.exists(recording.filepath):
            # Stream het volledige bestand
            def generate():
                with open(recording.filepath, 'rb') as f:
                    while True:
                        data = f.read(1024)
                        if not data:
                            break
                        yield data
                    
            return Response(
                generate(),
                mimetype='audio/mpeg',
                headers={'Content-Disposition': f'attachment; filename="{filename}"'}
            )
        else:
            # TODO: Haal bestand op uit S3 als lokaal niet beschikbaar
            abort(404, description="Audio bestand niet lokaal beschikbaar")
    except Exception as e:
        logger.error(f"Fout bij downloaden audio: {str(e)}")
        abort(500, description=f"Error: {str(e)}")
EOL
        chmod 755 "$INSTALL_DIR/player.py"
        chown radiologger:radiologger "$INSTALL_DIR/player.py"
        echo -e "${GREEN}✅ player.py succesvol aangemaakt${NC}"
    fi
    
    # Controleer en creëer main.py als deze ontbreekt
    if [[ " ${missende_bestanden[*]} " =~ " main.py " ]]; then
        echo "📝 main.py aanmaken..."
        cat > "$INSTALL_DIR/main.py" << 'EOL'
import os
import sys
import logging

# Voeg de huidige map toe aan Python's module zoekpad
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

# Configureer logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('main')

# Importeer app.py
try:
    from app import app
    
    # Importeer routes
    import routes
    
    # Importeer player module (voor opname weergave)
    try:
        import player
        logger.info("Player module geladen")
    except ImportError as e:
        logger.error(f"Kon player module niet laden: {str(e)}")
    
    # Start scheduler
    try:
        from logger import start_scheduler
        from apscheduler.schedulers.background import BackgroundScheduler
        
        scheduler = BackgroundScheduler()
        with app.app_context():
            start_scheduler(scheduler)
        logger.info("Scheduler gestart")
    except Exception as e:
        logger.error(f"Kon scheduler niet starten: {str(e)}")

except ImportError as e:
    logger.critical(f"Kon app niet laden: {str(e)}")
    sys.exit(1)

# Server starter
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
EOL
        chmod 755 "$INSTALL_DIR/main.py"
        chown radiologger:radiologger "$INSTALL_DIR/main.py"
        echo -e "${GREEN}✅ main.py succesvol aangemaakt${NC}"
    fi
    
    # Controleer en creëer app.py als deze ontbreekt
    if [[ " ${missende_bestanden[*]} " =~ " app.py " ]]; then
        echo "📝 app.py aanmaken..."
        cat > "$INSTALL_DIR/app.py" << 'EOL'
import os
import logging
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.orm import DeclarativeBase
from flask_login import LoginManager

# Configureer logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Basisklasse voor SQLAlchemy modellen
class Base(DeclarativeBase):
    pass

# Initialiseer database
db = SQLAlchemy(model_class=Base)

# Initialiseer app
app = Flask(__name__)

# Configureer app
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL")
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "development-key-replace-in-production")

# Logging van database configuratie (zonder wachtwoorden)
db_url = os.environ.get("DATABASE_URL", "")
if db_url:
    masked_url = db_url.replace(db_url.split('@')[0].split(':')[-1], '****')
    logger.info(f"App configuratie geladen. Database: {masked_url}")

# Initialiseer de database met de app
db.init_app(app)

# Initialiseer login manager
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# Error handlers
@app.errorhandler(404)
def not_found_error(error):
    from flask import render_template
    return render_template('404.html'), 404

@app.errorhandler(500)
def internal_error(error):
    from flask import render_template
    db.session.rollback()
    return render_template('500.html'), 500

# Context hook voor database cleanup
@app.teardown_request
def teardown_request(exception=None):
    if exception:
        db.session.rollback()
    db.session.remove()

# Initialiseer auth blueprint
try:
    from auth import auth_bp
    app.register_blueprint(auth_bp)
except ImportError as e:
    logger.warning(f"Kon auth blueprint niet registreren: {str(e)}")

# Controleer of mappen bestaan
for dir_path in [os.environ.get('RECORDINGS_DIR', 'recordings'), 
                os.environ.get('LOGS_DIR', 'logs')]:
    if not os.path.exists(dir_path):
        try:
            os.makedirs(dir_path, exist_ok=True)
            logger.info(f"Map {dir_path} aangemaakt")
        except Exception as e:
            logger.error(f"Kon map {dir_path} niet aanmaken: {str(e)}")

# Ontwikkelserver starter
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOL
        chmod 755 "$INSTALL_DIR/app.py"
        chown radiologger:radiologger "$INSTALL_DIR/app.py"
        echo -e "${GREEN}✅ app.py succesvol aangemaakt${NC}"
    fi
    
    # Maak templates map en basis templates
    if [ ! -d "$INSTALL_DIR/templates" ]; then
        echo "📝 templates map aanmaken..."
        mkdir -p "$INSTALL_DIR/templates"
        chown radiologger:radiologger "$INSTALL_DIR/templates"
        chmod 755 "$INSTALL_DIR/templates"
        
        # Basistemplate
        cat > "$INSTALL_DIR/templates/base.html" << 'EOL'
<!DOCTYPE html>
<html>
<head>
    <title>{% block title %}Radiologger{% endblock %}</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css">
    {% block head %}{% endblock %}
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <div class="container-fluid">
            <a class="navbar-brand" href="/">Radiologger</a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav me-auto">
                    <li class="nav-item">
                        <a class="nav-link" href="{{ url_for('list_recordings') }}">Opnames</a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="{{ url_for('admin') }}">Admin</a>
                    </li>
                </ul>
                <div class="d-flex">
                    {% if current_user.is_authenticated %}
                    <span class="navbar-text me-3">
                        Ingelogd als {{ current_user.username }} ({{ current_user.role }})
                    </span>
                    <a href="{{ url_for('logout') }}" class="btn btn-outline-light btn-sm">Uitloggen</a>
                    {% else %}
                    <a href="{{ url_for('login') }}" class="btn btn-outline-light btn-sm">Inloggen</a>
                    {% endif %}
                </div>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        {% with messages = get_flashed_messages(with_categories=true) %}
        {% if messages %}
            {% for category, message in messages %}
            <div class="alert alert-{{ category }}">{{ message }}</div>
            {% endfor %}
        {% endif %}
        {% endwith %}

        {% block content %}{% endblock %}
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js"></script>
    {% block scripts %}{% endblock %}
</body>
</html>
EOL
        
        # Error templates
        cat > "$INSTALL_DIR/templates/404.html" << 'EOL'
{% extends "base.html" %}

{% block title %}Pagina Niet Gevonden{% endblock %}

{% block content %}
<div class="card text-center">
    <div class="card-header">
        <h1>404 - Pagina Niet Gevonden</h1>
    </div>
    <div class="card-body">
        <p>De opgevraagde pagina kon niet worden gevonden.</p>
        <a href="{{ url_for('index') }}" class="btn btn-primary">Terug naar Home</a>
    </div>
</div>
{% endblock %}
EOL

        cat > "$INSTALL_DIR/templates/500.html" << 'EOL'
{% extends "base.html" %}

{% block title %}Server Fout{% endblock %}

{% block content %}
<div class="card text-center">
    <div class="card-header">
        <h1>500 - Interne Server Fout</h1>
    </div>
    <div class="card-body">
        <p>Er is een fout opgetreden bij het verwerken van uw verzoek.</p>
        <a href="{{ url_for('index') }}" class="btn btn-primary">Terug naar Home</a>
    </div>
</div>
{% endblock %}
EOL

        cat > "$INSTALL_DIR/templates/error.html" << 'EOL'
{% extends "base.html" %}

{% block title %}{{ title|default('Fout') }}{% endblock %}

{% block content %}
<div class="card">
    <div class="card-header">
        <h1>Fout</h1>
    </div>
    <div class="card-body">
        <div class="alert alert-danger">
            {{ message }}
        </div>
        <a href="{{ url_for('index') }}" class="btn btn-primary">Terug naar Home</a>
    </div>
</div>
{% endblock %}
EOL

        echo -e "${GREEN}✅ Templates succesvol aangemaakt${NC}"
    fi
else
    echo -e "${GREEN}✅ Alle kritieke bestanden zijn aanwezig${NC}"
fi

# 7. Python virtuele omgeving en dependencies installeren
echo ""
echo "Stap 7: Python virtuele omgeving en dependencies installeren..."
cd "$INSTALL_DIR"
python3 -m venv venv
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --upgrade setuptools wheel

# Installeer benodigde packages
echo "Installeren van benodigde packages..."
"$INSTALL_DIR/venv/bin/pip" install flask flask-login flask-sqlalchemy flask-wtf flask-migrate
"$INSTALL_DIR/venv/bin/pip" install python-dotenv sqlalchemy apscheduler boto3 requests
"$INSTALL_DIR/venv/bin/pip" install trafilatura psycopg2-binary werkzeug gunicorn
"$INSTALL_DIR/venv/bin/pip" install email-validator wtforms psutil
echo -e "${GREEN}✅ Python virtuele omgeving en packages geïnstalleerd${NC}"

# 8. PostgreSQL database instellen
echo ""
echo "Stap 8: PostgreSQL database instellen..."

# Genereer een random wachtwoord
DB_PASSWORD=$(openssl rand -hex 12)

# Maak databse en gebruiker aan
echo "Database en gebruiker aanmaken..."
sudo -u postgres psql -c "CREATE USER radiologger WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE radiologger OWNER radiologger;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE radiologger TO radiologger;"
echo -e "${GREEN}✅ PostgreSQL database en gebruiker aangemaakt${NC}"

# 9. Configuratie bestand (.env) aanmaken
echo ""
echo "Stap 9: Configuratie bestand aanmaken..."

# Genereer een geheime sleutel
SECRET_KEY=$(openssl rand -hex 24)

# Maak het .env bestand
cat > "$INSTALL_DIR/.env" << EOL
FLASK_APP=main.py
FLASK_ENV=production
DATABASE_URL=postgresql://radiologger:$DB_PASSWORD@localhost:5432/radiologger
FLASK_SECRET_KEY=$SECRET_KEY

# Mappen configuratie
RECORDINGS_DIR=/var/lib/radiologger/recordings
LOGS_DIR=/var/log/radiologger
RETENTION_DAYS=30
LOCAL_FILE_RETENTION=0

# API endpoints
OMROEP_LVC_URL=https://gemist.omroeplvc.nl/
DENNIS_API_URL=https://logger.dennishoogeveenmedia.nl/api/stations.json

# Systeem configuratie
FFMPEG_PATH=/usr/bin/ffmpeg

# S3 storage configuratie - later in te stellen door de gebruiker
WASABI_ACCESS_KEY=
WASABI_SECRET_KEY=
WASABI_BUCKET=
WASABI_REGION=eu-central-1
WASABI_ENDPOINT_URL=https://s3.eu-central-1.wasabisys.com
EOL

# Rechten instellen
chown radiologger:radiologger "$INSTALL_DIR/.env"
chmod 600 "$INSTALL_DIR/.env"
echo -e "${GREEN}✅ Configuratie bestand aangemaakt${NC}"

# 10. Systemd service bestand aanmaken
echo ""
echo "Stap 10: Systemd service bestand aanmaken..."
cat > /etc/systemd/system/radiologger.service << EOL
[Unit]
Description=Radiologger Web Application
After=network.target postgresql.service

[Service]
User=radiologger
Group=radiologger
WorkingDirectory=$INSTALL_DIR
Environment="HOME=$INSTALL_DIR"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 --chdir $INSTALL_DIR main:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

# 11. Nginx configuratie aanmaken
echo ""
echo "Stap 11: Nginx configuratie aanmaken..."
cat > /etc/nginx/sites-available/radiologger << EOL
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# Maak symbolische link aan en verwijder default configuratie
ln -sf /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 12. Services starten
echo ""
echo "Stap 12: Services starten..."
systemctl daemon-reload
systemctl enable radiologger
systemctl start radiologger
systemctl restart nginx
echo -e "${GREEN}✅ Services gestart${NC}"

# 13. Diagnose tools aanmaken
echo ""
echo "Stap 13: Diagnose tools aanmaken..."

# fix_permissions.sh
cat > "$INSTALL_DIR/fix_permissions.sh" << 'EOL'
#!/bin/bash
# Radiologger fix permissions script
# Dit script herstelt alle permissies voor de radiologger applicatie

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

echo "Radiologger Permissie Fix Script"
echo "=============================="
echo ""

# Fix permissies voor hoofdmappen
echo "Permissies fixen voor hoofdmappen..."
chown -R radiologger:radiologger /opt/radiologger
chmod -R 755 /opt/radiologger
chmod 600 /opt/radiologger/.env 2>/dev/null || echo "Waarschuwing: .env bestand niet gevonden"

# Fix permissies voor log mappen
echo "Permissies fixen voor log mappen..."
if [ -d /var/log/radiologger ]; then
    chown -R radiologger:radiologger /var/log/radiologger
    chmod -R 755 /var/log/radiologger
else
    echo "Waarschuwing: Log map niet gevonden, aanmaken..."
    mkdir -p /var/log/radiologger
    chown -R radiologger:radiologger /var/log/radiologger
    chmod -R 755 /var/log/radiologger
fi

# Fix permissies voor opname mappen
echo "Permissies fixen voor opname mappen..."
if [ -d /var/lib/radiologger/recordings ]; then
    chown -R radiologger:radiologger /var/lib/radiologger/recordings
    chmod -R 755 /var/lib/radiologger/recordings
else
    echo "Waarschuwing: Opname map niet gevonden, aanmaken..."
    mkdir -p /var/lib/radiologger/recordings
    chown -R radiologger:radiologger /var/lib/radiologger/recordings
    chmod -R 755 /var/lib/radiologger/recordings
fi

# Fix HOME directory in systemd service
echo "Controleren en fixen van HOME directory in systemd service..."
if [ -f /etc/systemd/system/radiologger.service ]; then
    if ! grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
        echo "HOME directory toevoegen aan service..."
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✅ HOME directory toegevoegd aan service, systemd herladen"
    else
        echo "✅ HOME directory al ingesteld in service"
    fi
else
    echo "❌ Systemd service bestand niet gevonden!"
fi

# Controleer EnvironmentFile in systemd service
echo "Controleren en fixen van EnvironmentFile in systemd service..."
if [ -f /etc/systemd/system/radiologger.service ]; then
    if ! grep -q "EnvironmentFile=/opt/radiologger/.env" /etc/systemd/system/radiologger.service; then
        echo "EnvironmentFile toevoegen aan service..."
        sed -i '/\[Service\]/a EnvironmentFile=/opt/radiologger/.env' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✅ EnvironmentFile toegevoegd aan service, systemd herladen"
    else
        echo "✅ EnvironmentFile al ingesteld in service"
    fi
fi

# Controleer of main.py bestaat
echo "Controleren of main.py bestaat..."
if [ ! -f /opt/radiologger/main.py ]; then
    echo "❌ main.py bestand niet gevonden, aanmaken..."
    cat > /opt/radiologger/main.py << 'EOLMAIN'
import os
import sys
import logging

# Voeg de huidige map toe aan Python's module zoekpad
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

# Configureer logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('main')

# Importeer app.py
try:
    from app import app
    
    # Importeer routes
    import routes
    
    # Importeer player module (voor opname weergave)
    try:
        import player
        logger.info("Player module geladen")
    except ImportError as e:
        logger.error(f"Kon player module niet laden: {str(e)}")
    
    # Start scheduler
    try:
        from logger import start_scheduler
        from apscheduler.schedulers.background import BackgroundScheduler
        
        scheduler = BackgroundScheduler()
        with app.app_context():
            start_scheduler(scheduler)
        logger.info("Scheduler gestart")
    except Exception as e:
        logger.error(f"Kon scheduler niet starten: {str(e)}")

except ImportError as e:
    logger.critical(f"Kon app niet laden: {str(e)}")
    sys.exit(1)

# Server starter
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
EOLMAIN
    chmod 755 /opt/radiologger/main.py
    chown radiologger:radiologger /opt/radiologger/main.py
    echo "✅ main.py succesvol aangemaakt"
else
    echo "✅ main.py bestand gevonden"
fi

# Controleer of venv bestaat en permissies
echo "Controleren van Python virtual environment..."
if [ -d /opt/radiologger/venv ]; then
    echo "✅ Python virtual environment gevonden, permissies fixen..."
    chown -R radiologger:radiologger /opt/radiologger/venv
    chmod -R 755 /opt/radiologger/venv
else
    echo "❌ Python virtual environment niet gevonden!"
fi

# Herstart services
echo ""
echo "Herstarten van services..."
echo "Radiologger service herstarten..."
systemctl restart radiologger
echo "Nginx herstarten..."
systemctl restart nginx

# Toon status
echo ""
echo "Service status na fix:"
systemctl status radiologger --no-pager -n 5

echo ""
echo "✅ Radiologger permissies succesvol gerepareerd!"
echo "Controleer de webinterface door te navigeren naar je domein"
EOL

# diagnose_502.sh
cat > "$INSTALL_DIR/diagnose_502.sh" << 'EOL'
#!/bin/bash
# Diagnose script voor 502 Bad Gateway in Radiologger
# Dit script controleert de status van de service, logs, en configuraties

echo "Radiologger Diagnose Script"
echo "==========================="
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Controleer systemd service status
echo "Controleren van Radiologger service status..."
systemctl status radiologger
SERVICE_RUNNING=$?

if [ $SERVICE_RUNNING -ne 0 ]; then
    echo "⚠️ De Radiologger service draait niet!"
    echo "Start poging..."
    systemctl start radiologger
    sleep 3
    systemctl status radiologger
    SERVICE_RUNNING=$?
    
    if [ $SERVICE_RUNNING -ne 0 ]; then
        echo "❌ De service kon niet worden gestart!"
        echo "Servicelog bekijken voor meer details:"
        journalctl -u radiologger --no-pager -n 50
    else
        echo "✅ De service is nu gestart!"
    fi
else
    echo "✅ De Radiologger service draait!"
fi

# Controleer poortbinding
echo ""
echo "Controleren op poortbinding port 5000..."
PORT_OPEN=$(ss -tuln | grep :5000)

if [ -z "$PORT_OPEN" ]; then
    echo "❌ Geen proces luistert op poort 5000!"
else
    echo "✅ Er is een proces dat luistert op poort 5000: $PORT_OPEN"
fi

# Controleer nginx configuratie
echo ""
echo "Controleren van Nginx configuratie..."
nginx -t

# Controleren of de proxy werkt via curl
echo ""
echo "Testen van lokale verbinding naar applicatie..."
curl -s -I http://127.0.0.1:5000 || echo "❌ Kan geen verbinding maken met de applicatie!"

# Controleer permissies
echo ""
echo "Controleren van permissies voor belangrijke mappen..."
ls -ld /opt/radiologger
ls -ld /var/log/radiologger

# Controleer main.py bestand (cruciaal voor Gunicorn)
echo ""
echo "Controleren op main.py bestand (belangrijk voor Gunicorn)..."
if [ -f /opt/radiologger/main.py ]; then
    echo "✅ main.py bestand gevonden"
    # Toon de inhoud
    echo "Inhoud van main.py:"
    cat -n /opt/radiologger/main.py
    # Controleer bestandsrechten
    ls -l /opt/radiologger/main.py
else
    echo "❌ main.py bestand niet gevonden! Dit veroorzaakt 'ModuleNotFoundError: No module named main'"
    echo "Dit bestand is essentieel voor Gunicorn om de applicatie te starten."
fi

# Controleer Python omgeving
echo ""
echo "Controleren Python omgeving..."
if [ -f /opt/radiologger/venv/bin/python ]; then
    echo "✅ Python virtual environment gevonden"
    /opt/radiologger/venv/bin/python --version
    echo "Geïnstalleerde Python pakketten:"
    /opt/radiologger/venv/bin/pip freeze | grep -E "(flask|gunicorn|sqlalchemy)"
else
    echo "❌ Python virtual environment niet gevonden!"
fi

# Controleer applicatie logs
echo ""
echo "Checken applicatie logs..."
if [ -f /var/log/radiologger/error.log ]; then
    echo "Laatste 10 regels van error.log:"
    tail -n 10 /var/log/radiologger/error.log
else
    echo "❌ Applicatie error log niet gevonden!"
fi

# Nginx error logs
echo ""
echo "Checken Nginx logs..."
if [ -f /var/log/nginx/radiologger_error.log ]; then
    echo "Laatste 10 regels van nginx error log:"
    tail -n 10 /var/log/nginx/radiologger_error.log
else
    echo "❌ Nginx error log niet gevonden!"
fi

# Fix-acties
echo ""
echo "Mogelijke oplossingen:"
echo "1. Herstarten van de service:"
echo "   sudo systemctl restart radiologger"
echo ""
echo "2. Herstarten van Nginx:"
echo "   sudo systemctl restart nginx"
echo ""
echo "3. Controleer .env bestand:"
echo "   sudo nano /opt/radiologger/.env"
echo ""
echo "4. Fix permissies (beste optie):"
echo "   sudo bash /opt/radiologger/fix_permissions.sh"
echo ""
echo "   Of handmatig:"
echo "   sudo chown -R radiologger:radiologger /opt/radiologger"
echo "   sudo chown -R radiologger:radiologger /var/log/radiologger"
echo ""
echo "5. Handmatig starten om details te zien:"
echo "   sudo -u radiologger /opt/radiologger/venv/bin/gunicorn --chdir /opt/radiologger --bind 0.0.0.0:5000 main:app"
echo ""
echo "6. Als niets anders werkt, overweeg het volgende:"
echo "   sudo bash /opt/radiologger/find_env_issues.sh"
echo ""

# Automatische fix-acties
echo "Wil je automatisch een aantal standaard fixes proberen? (j/n)"
read -r AUTO_FIX

if [[ "$AUTO_FIX" =~ ^[jJ]$ ]]; then
    echo "Automatische fixes uitvoeren..."
    
    # Fix permissies
    echo "Permissies fixen met fix_permissions.sh script..."
    if [ -f /opt/radiologger/fix_permissions.sh ]; then
        bash /opt/radiologger/fix_permissions.sh
    else
        echo "fix_permissions.sh script niet gevonden, handmatige fix..."
        chown -R radiologger:radiologger /opt/radiologger
        chown -R radiologger:radiologger /var/log/radiologger
        chmod 755 /opt/radiologger
        chmod 755 /var/log/radiologger
        
        # Fix HOME in service als het script niet bestaat
        if [ -f /etc/systemd/system/radiologger.service ]; then
          if ! grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
            echo "HOME directory toevoegen aan service..."
            sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
            systemctl daemon-reload
          fi
        fi
    fi
    
    # Controleer socket
    echo "Poort 5000 resetten..."
    fuser -k 5000/tcp 2>/dev/null || true
    
    # Herstarten van services
    echo "Services herstarten..."
    systemctl restart radiologger
    systemctl restart nginx
    
    echo "Wachten op services om op te starten..."
    sleep 5
    
    # Toon resultaten
    echo "Status na fixes:"
    systemctl status radiologger --no-pager -n 10
    curl -s -I http://127.0.0.1:5000 || echo "❌ Kan nog steeds geen verbinding maken met de applicatie!"
fi

echo ""
echo "Diagnose voltooid! Als de problemen blijven bestaan, gebruik de getoonde informatie"
echo "om te begrijpen wat er mis is en volg de voorgestelde oplossingen."
EOL

# Maak diagnose scripts uitvoerbaar
chmod +x "$INSTALL_DIR/fix_permissions.sh"
chmod +x "$INSTALL_DIR/diagnose_502.sh"
chown radiologger:radiologger "$INSTALL_DIR/fix_permissions.sh"
chown radiologger:radiologger "$INSTALL_DIR/diagnose_502.sh"
echo -e "${GREEN}✅ Diagnose scripts aangemaakt${NC}"

# 14. Verificatie
echo ""
echo "Stap 14: Installatie verifiëren..."

# Controleer of services draaien
echo "Controleren of services draaien..."
systemctl status radiologger --no-pager -n 5
echo ""
systemctl status nginx --no-pager -n 5
echo ""

# Controleer of de site bereikbaar is
echo "Controleren of de site bereikbaar is..."
curl -s -I http://localhost

# Eindresultaat
echo ""
echo "====== RADIOLOGGER INSTALLATIE VOLTOOID ======"
echo ""
echo "De Radiologger applicatie is succesvol geïnstalleerd en geconfigureerd."
echo "De applicatie draait op http://localhost en is toegankelijk via de webbrowser."
echo ""
echo "Belangrijke informatie:"
echo "- Database gebruiker: radiologger"
echo "- Database wachtwoord: $DB_PASSWORD"
echo "- Installatiemap: $INSTALL_DIR"
echo "- Opnamemap: /var/lib/radiologger/recordings"
echo "- Logmap: /var/log/radiologger"
echo ""
echo "Voor eventuele problemen, gebruik de volgende diagnose scripts:"
echo "- sudo bash $INSTALL_DIR/fix_permissions.sh"
echo "- sudo bash $INSTALL_DIR/diagnose_502.sh"
echo ""
echo "Bij je eerste inlog kun je de configuratie voor Wasabi S3 opslag instellen."
echo ""
echo "Bedankt voor het installeren van Radiologger!"