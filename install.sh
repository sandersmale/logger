#!/bin/bash
# Radiologger installatiescript voor Ubuntu 24.04
# Dit script installeert en configureert de Radiologger applicatie

# Controleer of het script als root draait
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Controleer of we op Ubuntu 24.04 draaien
if ! grep -q "Ubuntu" /etc/os-release || ! grep -q "24.04" /etc/os-release; then
    echo "WAARSCHUWING: Dit script is getest op Ubuntu 24.04. Je gebruikt een andere versie."
    echo "De installatie gaat door, maar er kunnen compatibiliteitsproblemen optreden."
fi

# Controleer internetverbinding
if ! ping -c 1 google.com >/dev/null 2>&1; then
    echo "FOUT: Geen internetverbinding gevonden"
    exit 1
fi

# Controleer beschikbare schijfruimte (minimaal 1GB)
available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_space" -lt 1 ]; then
    echo "FOUT: Onvoldoende schijfruimte beschikbaar (minimaal 1GB nodig)"
    exit 1
fi

set -e  # Stop bij fouten

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd"
   exit 1
fi

echo "Radiologger installatiescript voor Ubuntu 24.04"
echo "==============================================="
echo ""

# Info over wat het script gaat doen
echo "Dit script zal het volgende doen:"
echo "1. Systeem updaten en benodigde pakketten installeren"
echo "2. PostgreSQL database instellen"
echo "3. Radiologger gebruiker aanmaken en mapstructuur opzetten"
echo "4. Python virtuele omgeving en dependencies installeren"
echo "5. Systemd service instellen"
echo "6. Nginx configureren"
echo "7. Optioneel: SSL certificaat genereren via Let's Encrypt"
echo ""

# Configureer algemene installatie-instellingen
export DEBIAN_FRONTEND=noninteractive
export UCF_FORCE_CONFFOLD=1  # Behoud bestaande configuratiebestanden
export NEEDRESTART_MODE=a    # Automatisch herstarten van services
export NEEDRESTART_SUSPEND=1 # Onderdruk needrestart prompts

# Vraag ALLE benodigde configuratiegegevens zodat de installatie zonder onderbrekingen kan verlopen
echo "Voor de installatie zijn de volgende gegevens nodig:"
echo "1. PostgreSQL database gebruikerswachtwoord"
echo "2. Wasabi cloud storage gegevens"
echo "3. Server- en installatieconfiguratie"
echo ""

# Database configuratie
read -p "Kies een wachtwoord voor de PostgreSQL radiologger gebruiker: " db_password

# Wasabi cloud storage
read -p "Voer de Wasabi access key in: " wasabi_access
read -p "Voer de Wasabi secret key in: " wasabi_secret
read -p "Voer de Wasabi bucket naam in: " wasabi_bucket
read -p "Voer de Wasabi regio in (standaard: eu-central-1): " wasabi_region
wasabi_region=${wasabi_region:-eu-central-1}

# Server configuratie
read -p "Server domeinnaam voor Nginx (standaard: logger.pilotradio.nl): " server_domain
server_domain=${server_domain:-logger.pilotradio.nl}

# SSL configuratie
read -p "SSL certificaat installeren? (j/n, standaard: j): " ssl_response
ssl_response=${ssl_response:-j}

# Radiostations configuratie
read -p "Standaard radiostations importeren? (j/n, standaard: j): " use_default_stations
use_default_stations=${use_default_stations:-j}

echo "Alle benodigde gegevens ontvangen. De installatie zal nu zonder verdere onderbrekingen verlopen..."
echo ""

echo "Stap 1: Systeem updaten en pakketten installeren..."
apt update
apt upgrade -y

# Controleer of er een lijst van benodigde software is
if [ -f "benodigde_software.txt" ]; then
    echo "Benodigde softwarelijst gevonden. Installeren van vermelde pakketten..."
    # Lees het bestand en installeer elk pakket
    mapfile -t pakketten < benodigde_software.txt
    for pakket in "${pakketten[@]}"; do
        if [ -n "$pakket" ] && [[ ! "$pakket" =~ ^# ]]; then  # Sla lege regels en commentaar over
            echo "Installeren van $pakket..."
            apt install -y "$pakket"
        fi
    done
else
    echo "Geen benodigde_software.txt gevonden. Installeren van standaard pakketten..."
    
    # Installeer nieuwste Python-gerelateerde pakketten
    apt install -y python3 python3-pip python3-venv python3-dev
    
    # Controleer of PostgreSQL 16 beschikbaar is en installeer het
    if apt-cache show postgresql-16 &> /dev/null; then
        echo "PostgreSQL 16 beschikbaar, installeren..."
        apt install -y postgresql-16 postgresql-contrib-16 postgresql-client-16
    else
        echo "PostgreSQL 16 niet beschikbaar, installeren van nieuwste beschikbare versie..."
        apt install -y postgresql postgresql-contrib
    fi
    
    # Multimedia tools
    apt install -y ffmpeg
    
    # Webserver
    apt install -y nginx
    
    # SSL certificaten
    apt install -y certbot python3-certbot-nginx
    
    # Ontwikkelingstools
    apt install -y build-essential libpq-dev git
    
    # Extra tools die handig kunnen zijn voor beheer
    apt install -y htop curl vim rsync
fi

# Openssh-server configuratie automatiseren (geen prompts)
export DEBIAN_FRONTEND=noninteractive
echo 'openssh-server openssh-server/sshd_config_backup boolean true' | debconf-set-selections
echo 'openssh-server openssh-server/sshd_config select keep_current' | debconf-set-selections

echo ""
echo "Stap 2: PostgreSQL database instellen..."
# Gebruik het wachtwoord dat al eerder is opgevraagd
sudo -u postgres psql -c "CREATE USER radiologger WITH PASSWORD '$db_password';"
sudo -u postgres psql -c "CREATE DATABASE radiologger OWNER radiologger;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE radiologger TO radiologger;"

echo ""
echo "Stap 3: Radiologger gebruiker aanmaken en mapstructuur opzetten..."
useradd -m -s /bin/bash radiologger 2>/dev/null || echo "Gebruiker bestaat al"
mkdir -p /opt/radiologger
mkdir -p /var/log/radiologger
mkdir -p /var/lib/radiologger/recordings
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger

echo ""
echo "Stap 3b: Radiologger applicatiebestanden kopiëren..."
# Kopieer alle bestanden naar de installatie map
# We gaan uit van het feit dat het script in dezelfde directory staat als de applicatiebestanden
# of dat de gebruiker de repository reeds heeft gekloned met git
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [ -f "$SCRIPT_DIR/main.py" ]; then
    echo "Kopiëren van lokale bestanden vanaf $SCRIPT_DIR..."
    cp -r "$SCRIPT_DIR"/* /opt/radiologger/
elif [ -d "/tmp/radiologger" ]; then
    echo "Kopiëren van bestanden uit /tmp/radiologger..."
    cp -r /tmp/radiologger/* /opt/radiologger/
else
    echo "Radiologger bestanden niet gevonden in huidige map of in /tmp/radiologger."
    echo "Ophalen van bestanden van GitHub repository..."
    git clone https://github.com/sandersmale/logger.git /tmp/radiologger_tmp
    cp -r /tmp/radiologger_tmp/* /opt/radiologger/
    rm -rf /tmp/radiologger_tmp
fi
chown -R radiologger:radiologger /opt/radiologger

echo ""
echo "Stap 4: Python virtuele omgeving en dependencies installeren..."
cd /opt/radiologger || exit 1

# Maak een nieuwe virtuele omgeving
python3 -m venv venv

# Upgrade pip zelf
/opt/radiologger/venv/bin/pip install --upgrade pip

# Installeer/upgrade setuptools en wheel als basis
/opt/radiologger/venv/bin/pip install --upgrade setuptools wheel

# Controleer en installeer de dependencies uit het requirements bestand
if [ -f "/opt/radiologger/export_requirements.txt" ]; then
    echo "Requirements bestand gevonden op standaardlocatie."
    /opt/radiologger/venv/bin/pip install -r /opt/radiologger/export_requirements.txt
elif [ -f "/opt/radiologger/requirements.txt" ]; then
    echo "Alternative requirements.txt gevonden."
    /opt/radiologger/venv/bin/pip install -r /opt/radiologger/requirements.txt
else
    echo "Geen requirements-bestand gevonden. Installeer essentiële pakketten handmatig."
    # Installeer essentiële pakketten handmatig als fallback
    /opt/radiologger/venv/bin/pip install flask flask-login flask-sqlalchemy flask-wtf flask-migrate
    /opt/radiologger/venv/bin/pip install python-dotenv sqlalchemy apscheduler boto3 requests
    /opt/radiologger/venv/bin/pip install trafilatura psycopg2-binary werkzeug gunicorn
    /opt/radiologger/venv/bin/pip install email-validator wtforms psutil
fi

# Installeer/upgrade extra benodigde pakketten
/opt/radiologger/venv/bin/pip install --upgrade gunicorn
/opt/radiologger/venv/bin/pip install --upgrade boto3
/opt/radiologger/venv/bin/pip install --upgrade psycopg2-binary

echo ""
echo "Stap 5: Configuratie bestand aanmaken..."
# Genereer een automatische geheime sleutel
secret_key=$(openssl rand -hex 24)
echo "Automatisch gegenereerde geheime sleutel: $secret_key"

# Wasabi gegevens zijn al aan het begin opgevraagd

# Stel standaardwaarden in voor de API endpoints
dennis_api="https://logger.dennishoogeveenmedia.nl/api/stations.json"
echo "Dennis API URL ingesteld op: $dennis_api"
lvc_url="https://gemist.omroeplvc.nl/"
echo "Omroep LvC URL ingesteld op: $lvc_url"

# Maak het .env bestand
cat > /opt/radiologger/.env << EOL
FLASK_APP=main.py
FLASK_ENV=production
DATABASE_URL=postgresql://radiologger:$db_password@localhost:5432/radiologger
FLASK_SECRET_KEY=$secret_key

# Mappen configuratie
RECORDINGS_DIR=/var/lib/radiologger/recordings
LOGS_DIR=/var/log/radiologger
RETENTION_DAYS=30

# API endpoints
OMROEP_LVC_URL=$lvc_url
DENNIS_API_URL=$dennis_api

# Systeem configuratie
FFMPEG_PATH=/usr/bin/ffmpeg

# S3 storage configuratie
WASABI_ACCESS_KEY=$wasabi_access
WASABI_SECRET_KEY=$wasabi_secret
WASABI_BUCKET=$wasabi_bucket
WASABI_REGION=$wasabi_region
WASABI_ENDPOINT_URL=https://s3.$wasabi_region.wasabisys.com
EOL

# Rechten instellen
chown radiologger:radiologger /opt/radiologger/.env
chmod 600 /opt/radiologger/.env

echo ""
echo "Stap 6: Database initialiseren en vullen met basisgegevens..."
cd /opt/radiologger || exit 1

# Gebruik de eerder opgegeven keuze voor standaard stations
use_default_flag=""
if [[ "$use_default_stations" =~ ^[jJ]$ ]]; then
    use_default_flag="--use-default-stations"
    echo "Standaard stations uit de oude database worden gebruikt."
else
    echo "Voorbeeld stations worden gebruikt."
fi

# Controleer of setup_db.py bestaat, anders gebruik seed_data.py
if [ -f "setup_db.py" ]; then
    echo "setup_db.py gevonden, database initialiseren..."
    chmod +x setup_db.py
    sudo -u radiologger /opt/radiologger/venv/bin/python setup_db.py $use_default_flag
    setup_result=$?
    if [ $setup_result -ne 0 ]; then
        echo "WAARSCHUWING: setup_db.py gaf een fout, probeer handmatige initialisatie..."
        # Initialiseer tabel structuur direct met db.create_all() en verbeterde import robustheid
        cd /opt/radiologger
        sudo -u radiologger /opt/radiologger/venv/bin/python -c "
import sys
import os

# Expliciete directory toevoegen aan Python path
sys.path.insert(0, '/opt/radiologger')

try:
    from app import db, app
    with app.app_context():
        db.create_all()
    print('✅ Database tabellen aangemaakt')
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    sys.exit(1)
"
        if [ -f "seed_data.py" ]; then
            echo "Initialiseren van basisgegevens via seed_data.py..."
            sudo -u radiologger /opt/radiologger/venv/bin/python seed_data.py $use_default_flag
        fi
    fi
elif [ -f "seed_data.py" ]; then
    echo "setup_db.py niet gevonden, maar seed_data.py wel. Database initialiseren..."
    # Initialiseer tabel structuur direct met db.create_all() en verbeterde import robustheid
    cd /opt/radiologger
    sudo -u radiologger /opt/radiologger/venv/bin/python -c "
import sys
import os

# Expliciete directory toevoegen aan Python path
sys.path.insert(0, '/opt/radiologger')

try:
    from app import db, app
    with app.app_context():
        db.create_all()
    print('✅ Database tabellen aangemaakt')
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    sys.exit(1)
"
    # Vul de database met basisgegevens
    sudo -u radiologger /opt/radiologger/venv/bin/python seed_data.py $use_default_flag
else
    echo "Geen setup_db.py of seed_data.py gevonden. Initialiseer database basis tabellen..."
    # Creëer alleen de tabellen met verbeterde import robustheid en expliciet pad
    cd /opt/radiologger
    sudo -u radiologger /opt/radiologger/venv/bin/python -c "
import sys
import os

# Expliciete directory toevoegen aan Python path
sys.path.insert(0, '/opt/radiologger')

try:
    from app import db, app
    with app.app_context():
        db.create_all()
    print('✅ Database tabellen aangemaakt')
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    sys.exit(1)
"
    # Maak een admin gebruiker aan met verbeterde import robustheid
    cd /opt/radiologger
    sudo -u radiologger /opt/radiologger/venv/bin/python -c "
import sys
import os

# Expliciete directory toevoegen aan Python path
sys.path.insert(0, '/opt/radiologger')

try:
    from app import db, app
    from models import User
    from werkzeug.security import generate_password_hash
    with app.app_context():
        if User.query.count() == 0:
            admin = User(username='admin', role='admin', password_hash=generate_password_hash('radioadmin'))
            editor = User(username='editor', role='editor', password_hash=generate_password_hash('radioeditor'))
            listener = User(username='luisteraar', role='listener', password_hash=generate_password_hash('radioluisteraar'))
            db.session.add(admin)
            db.session.add(editor)
            db.session.add(listener)
            db.session.commit()
            print('✅ Standaard gebruikers aangemaakt')
except Exception as e:
    print(f'❌ Fout bij aanmaken gebruikers: {e}')
    sys.exit(1)
"
fi

echo ""
echo "Stap 7: Systemd service instellen..."
cat > /etc/systemd/system/radiologger.service << 'EOL'
[Unit]
Description=Radiologger Web Application
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=radiologger
Group=radiologger
WorkingDirectory=/opt/radiologger
Environment="PATH=/opt/radiologger/venv/bin"
EnvironmentFile=/opt/radiologger/.env
ExecStart=/opt/radiologger/venv/bin/gunicorn \
    --workers 3 \
    --bind 0.0.0.0:5000 \
    --log-level=info \
    --access-logfile=/var/log/radiologger/access.log \
    --error-logfile=/var/log/radiologger/error.log \
    --timeout 300 \
    main:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable radiologger
systemctl start radiologger

echo ""
echo "Stap 8: Nginx configureren voor $server_domain..."
cat > /etc/nginx/sites-available/radiologger << EOL
server {
    listen 80;
    server_name $server_domain;

    access_log /var/log/nginx/radiologger_access.log;
    error_log /var/log/nginx/radiologger_error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
    
    client_max_body_size 100M;
    
    location /static/ {
        alias /opt/radiologger/static/;
        expires 30d;
    }
    
    location = /favicon.ico {
        alias /opt/radiologger/static/favicon.ico;
    }
}
EOL

ln -s /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default  # Verwijder default site
nginx -t
systemctl restart nginx

echo ""
echo "Stap 9: SSL certificaat beheren..."
if [[ "$ssl_response" =~ ^[jJ]$ ]]; then
    echo "SSL certificaat wordt geïnstalleerd voor $server_domain..."
    certbot --nginx -d "$server_domain" --non-interactive --agree-tos --redirect
    echo "SSL certificaat voor $server_domain geïnstalleerd!"
else
    echo "SSL certificaat installatie overgeslagen op verzoek van gebruiker."
fi

echo ""
echo "Stap 10: Cron-taken instellen voor onderhoud..."
# Voeg crontab toe voor de radiologger gebruiker
(sudo -u radiologger crontab -l 2>/dev/null || echo "") | \
    { cat; echo "0 2 * * * find /var/log/radiologger -name \"*.log\" -type f -mtime +30 -delete"; } | \
    sudo -u radiologger crontab -

# Zet ook de crontab voor het downloaden van Omroep LvC bestanden
# 8 minuten na het uur (net als in de scheduler)
echo "Omroep LvC download taak instellen (8 minuten na het uur)..."
(sudo -u radiologger crontab -l 2>/dev/null) | \
    { cat; echo "8 * * * * cd /opt/radiologger && /opt/radiologger/venv/bin/python -c 'import sys, os; sys.path.insert(0, \"/opt/radiologger\"); from logger import download_omroeplvc; download_omroeplvc()' >> /var/log/radiologger/omroeplvc_cron.log 2>&1"; } | \
    sudo -u radiologger crontab -

echo ""
echo "====================================================================="
echo "✅ Radiologger is succesvol geïnstalleerd!"
if [[ "$ssl_response" =~ ^[jJ]$ ]]; then
    echo "De applicatie draait nu op https://$server_domain"
else
    echo "De applicatie draait nu op http://$server_domain"
fi
echo ""
echo "Standaard inloggegevens:"
echo "Admin: gebruikersnaam: admin, wachtwoord: radioadmin"
echo "Editor: gebruikersnaam: editor, wachtwoord: radioeditor"
echo "Luisteraar: gebruikersnaam: luisteraar, wachtwoord: radioluisteraar"
echo ""
echo "⚠️ BELANGRIJK: VERANDER DEZE WACHTWOORDEN DIRECT NA EERSTE INLOG!"
echo "====================================================================="