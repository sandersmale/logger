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
    echo "WAARSCHUWING: Dit script is getest op Ubuntu 24.04."
    echo "Je gebruikt een andere versie. Wil je toch doorgaan? (j/n)"
    read -r antwoord
    if [[ ! "$antwoord" =~ ^[jJ]$ ]]; then
        echo "Installatie geannuleerd"
        exit 1
    fi
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

echo ""
echo "Stap 1: Systeem updaten en pakketten installeren..."
apt update
apt upgrade -y

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

echo ""
echo "Stap 2: PostgreSQL database instellen..."
read -p "Kies een wachtwoord voor de PostgreSQL radiologger gebruiker: " db_password
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

# Installeer de dependencies uit het requirements bestand
/opt/radiologger/venv/bin/pip install -r export_requirements.txt

# Installeer/upgrade extra benodigde pakketten
/opt/radiologger/venv/bin/pip install --upgrade gunicorn
/opt/radiologger/venv/bin/pip install --upgrade boto3
/opt/radiologger/venv/bin/pip install --upgrade psycopg2-binary

echo ""
echo "Stap 5: Configuratie bestand aanmaken..."
# Genereer een automatische geheime sleutel
secret_key=$(openssl rand -hex 24)
echo "Automatisch gegenereerde geheime sleutel: $secret_key"

# Vraag om de benodigde configuratiewaardes
read -p "Voer de Wasabi access key in: " wasabi_access
read -p "Voer de Wasabi secret key in: " wasabi_secret
read -p "Voer de Wasabi bucket naam in: " wasabi_bucket
read -p "Voer de Wasabi regio in (standaard: eu-central-1): " wasabi_region
wasabi_region=${wasabi_region:-eu-central-1}

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

# Vraag of de gebruiker standaard stations wil
echo "Wil je de standaard radiostations uit de oude database gebruiken? (j/n): "
read -r use_default_stations
use_default_flag=""
if [[ "$use_default_stations" =~ ^[jJ]$ ]]; then
    use_default_flag="--use-default-stations"
    echo "Standaard stations uit de oude database worden gebruikt."
else
    echo "Voorbeeld stations worden gebruikt."
fi

# Controleer of het setup_db.py script bestaat, anders gebruik main.py
if [ -f "setup_db.py" ]; then
    sudo -u radiologger /opt/radiologger/venv/bin/python setup_db.py
else
    echo "setup_db.py niet gevonden, initialiseer database via main.py..."
    sudo -u radiologger /opt/radiologger/venv/bin/flask db upgrade
    sudo -u radiologger /opt/radiologger/venv/bin/python seed_data.py $use_default_flag
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
echo "Stap 8: Nginx configureren..."
cat > /etc/nginx/sites-available/radiologger << 'EOL'
server {
    listen 80;
    server_name logger.pilotradio.nl;

    access_log /var/log/nginx/radiologger_access.log;
    error_log /var/log/nginx/radiologger_error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
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
echo "Stap 9: Wil je een SSL certificaat genereren met Let's Encrypt? (j/n): "
read -r ssl_response
if [[ "$ssl_response" =~ ^[jJ]$ ]]; then
    certbot --nginx -d logger.pilotradio.nl
    echo "SSL certificaat geïnstalleerd!"
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
    { cat; echo "8 * * * * cd /opt/radiologger && /opt/radiologger/venv/bin/python -c 'from logger import download_omroeplvc; download_omroeplvc()' >> /var/log/radiologger/omroeplvc_cron.log 2>&1"; } | \
    sudo -u radiologger crontab -

echo ""
echo "====================================================================="
echo "Radiologger is succesvol geïnstalleerd!"
echo "De applicatie draait nu op https://logger.pilotradio.nl"
echo ""
echo "Standaard inloggegevens:"
echo "Admin: gebruikersnaam: admin, wachtwoord: radioadmin"
echo "Editor: gebruikersnaam: editor, wachtwoord: radioeditor"
echo "Luisteraar: gebruikersnaam: luisteraar, wachtwoord: radioluisteraar"
echo ""
echo "VERANDER DEZE WACHTWOORDEN DIRECT NA EERSTE INLOG!"
echo "====================================================================="