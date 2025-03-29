#!/bin/bash
# Radiologger installatiescript voor Ubuntu 24.04
# Dit script installeert en configureert de Radiologger applicatie

set -e  # Stop bij fouten

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd"
   exit 1
fi

echo "Radiologger installatiescript voor Ubuntu 24.04"
echo "==============================================="
echo ""

# Vraag om bevestiging
echo "Dit script zal het volgende doen:"
echo "1. Systeem updaten en benodigde pakketten installeren"
echo "2. PostgreSQL database instellen"
echo "3. Radiologger gebruiker aanmaken en mapstructuur opzetten"
echo "4. Python virtuele omgeving en dependencies installeren"
echo "5. Systemd service instellen"
echo "6. Nginx configureren"
echo "7. Optioneel: SSL certificaat genereren via Let's Encrypt"
echo ""
echo "Wil je doorgaan? (j/n): "
read -r response
if [[ ! "$response" =~ ^[jJ]$ ]]; then
    echo "Installatie geannuleerd"
    exit 0
fi

echo ""
echo "Stap 1: Systeem updaten en pakketten installeren..."
apt update
apt upgrade -y
apt install -y python3 python3-pip python3-venv 
apt install -y postgresql postgresql-contrib 
apt install -y ffmpeg
apt install -y nginx
apt install -y certbot python3-certbot-nginx
apt install -y build-essential libpq-dev git

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
echo "Stap 3b: Radiologger installeren vanaf GitHub..."
git clone https://github.com/sandersmale/logger.git /opt/radiologger
chown -R radiologger:radiologger /opt/radiologger

echo ""
echo "Stap 4: Python virtuele omgeving en dependencies installeren..."
cd /opt/radiologger || exit 1
python3 -m venv venv
/opt/radiologger/venv/bin/pip install --upgrade pip
/opt/radiologger/venv/bin/pip install -r export_requirements.txt
# Extra installeer gunicorn (voor productie)
/opt/radiologger/venv/bin/pip install gunicorn

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

# Controleer of het setup_db.py script bestaat, anders gebruik main.py
if [ -f "setup_db.py" ]; then
    sudo -u radiologger /opt/radiologger/venv/bin/python setup_db.py
else
    echo "setup_db.py niet gevonden, initialiseer database via main.py..."
    sudo -u radiologger /opt/radiologger/venv/bin/flask db upgrade
    sudo -u radiologger /opt/radiologger/venv/bin/python -c "from app import app, db; from seed_data import seed_initial_data; with app.app_context(): seed_initial_data()"
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
    
    # Voeg IP-adres toe voor hosts file/test
    listen 68.183.3.122:80;

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
(crontab -l 2>/dev/null || echo "") | \
    { cat; echo "0 2 * * * find /var/log/radiologger -name \"*.log\" -type f -mtime +30 -delete"; } | \
    crontab -

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