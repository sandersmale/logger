#!/bin/bash
# Radiologger installatiescript
# Dit script installeert de Radiologger applicatie op een Ubuntu 22.04/24.04 systeem
# en configureert alles wat nodig is voor een werkende installatie.

set -e

# Variabelen
INSTALL_DIR="/opt/radiologger"
GIT_REPO="https://github.com/sandersmale/logger.git"
LOG_DIR="/var/log/radiologger"
RECORDINGS_DIR="/var/lib/radiologger/recordings"
PG_VERSION="postgresql-15"
PYTHON_VERSION="python3"

# Kleuren voor output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Banner tonen
echo "==================================================="
echo "      RADIOLOGGER INSTALLATIE"
echo "==================================================="
echo ""
echo "Dit script installeert de Radiologger applicatie"
echo "op een Ubuntu 22.04/24.04 systeem."
echo ""
echo "BELANGRIJK: Zorg ervoor dat je dit script als root uitvoert."
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Dit script moet als root worden uitgevoerd!${NC}"
   exit 1
fi

# Functie voor foutafhandeling en logging
function handle_error {
    echo -e "${RED}ERROR: $1${NC}"
    echo "Controleer de installatielog voor meer details."
    exit 1
}

# 1. Systeempakketten installeren
echo -e "${GREEN}Stap 1: Benodigde systeempakketten installeren...${NC}"
apt-get update
apt-get install -y git python3 python3-venv python3-pip ffmpeg nginx curl wget $PG_VERSION $PG_VERSION-contrib

# 2. Database instellen
echo -e "${GREEN}Stap 2: PostgreSQL database instellen...${NC}"
echo "Aanmaken van database en gebruiker..."

# Genereer een veilig wachtwoord
DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

# PostgreSQL database en gebruiker aanmaken
sudo -u postgres psql -c "CREATE USER radiologger WITH PASSWORD '$DB_PASSWORD';" || true
sudo -u postgres psql -c "CREATE DATABASE radiologger OWNER radiologger;" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE radiologger TO radiologger;" || true

echo -e "${GREEN}✓ Database geconfigureerd${NC}"

# 3. Radiologger gebruiker aanmaken
echo -e "${GREEN}Stap 3: Radiologger systeemgebruiker aanmaken...${NC}"
if ! id -u radiologger >/dev/null 2>&1; then
    useradd -m -s /bin/bash -d $INSTALL_DIR radiologger
    echo -e "${GREEN}✓ Gebruiker radiologger aangemaakt${NC}"
else
    echo -e "${YELLOW}Gebruiker radiologger bestaat al${NC}"
fi

# 4. Mappen aanmaken en rechten instellen
echo -e "${GREEN}Stap 4: Mappen aanmaken en rechten instellen...${NC}"
mkdir -p $INSTALL_DIR
mkdir -p $LOG_DIR
mkdir -p $RECORDINGS_DIR

chown -R radiologger:radiologger $INSTALL_DIR
chown -R radiologger:radiologger $LOG_DIR
chown -R radiologger:radiologger $RECORDINGS_DIR

chmod -R 755 $INSTALL_DIR
chmod -R 755 $LOG_DIR
chmod -R 755 $RECORDINGS_DIR

echo -e "${GREEN}✓ Mappen aangemaakt en rechten ingesteld${NC}"

# 5. Applicatiebestanden ophalen van GitHub
echo -e "${GREEN}Stap 5: Applicatiebestanden ophalen van GitHub...${NC}"
# Verwijder temporaire map als deze bestaat
if [ -d "/tmp/radiologger_repo" ]; then
    rm -rf /tmp/radiologger_repo
fi

# Clone de repository
if ! git clone $GIT_REPO /tmp/radiologger_repo; then
    handle_error "Kan de GitHub repository niet clonen"
fi

# Kopieer bestanden, behalve .git map
rsync -a --exclude='.git' /tmp/radiologger_repo/ $INSTALL_DIR/

# Rechten instellen
chown -R radiologger:radiologger $INSTALL_DIR
chmod -R 755 $INSTALL_DIR

echo -e "${GREEN}✓ Applicatiebestanden opgehaald van GitHub${NC}"

# 6. Controleer en fix ontbrekende kritieke bestanden
echo -e "${GREEN}Stap 6: Controleren op kritieke bestanden...${NC}"
kritieke_bestanden=("main.py" "app.py" "routes.py" "player.py" "models.py")
missende_bestanden=()

for bestand in "${kritieke_bestanden[@]}"; do
    if [ ! -f "$INSTALL_DIR/$bestand" ]; then
        missende_bestanden+=("$bestand")
    fi
done

if [ ${#missende_bestanden[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️ De volgende kritieke bestanden ontbreken en worden opnieuw opgehaald:${NC}"
    for missend in "${missende_bestanden[@]}"; do
        echo "   - $missend"
    done
    
    # Probeer specifiek deze bestanden op te halen van GitHub
    for bestand in "${missende_bestanden[@]}"; do
        wget -q -O "$INSTALL_DIR/$bestand" "https://raw.githubusercontent.com/sandersmale/logger/main/$bestand" || \
        echo -e "${YELLOW}⚠️ Kon $bestand niet downloaden van GitHub${NC}"
        
        if [ -f "$INSTALL_DIR/$bestand" ]; then
            chown radiologger:radiologger "$INSTALL_DIR/$bestand"
            chmod 755 "$INSTALL_DIR/$bestand"
            echo -e "${GREEN}✓ $bestand succesvol opgehaald${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ Alle kritieke bestanden zijn aanwezig${NC}"
fi

# 7. Python virtuele omgeving instellen
echo -e "${GREEN}Stap 7: Python virtuele omgeving instellen...${NC}"
cd $INSTALL_DIR

# Virtuele omgeving aanmaken
$PYTHON_VERSION -m venv venv
$INSTALL_DIR/venv/bin/pip install --upgrade pip setuptools wheel

# Installeer vereisten
if [ -f "$INSTALL_DIR/export_requirements.txt" ]; then
    $INSTALL_DIR/venv/bin/pip install -r $INSTALL_DIR/export_requirements.txt
elif [ -f "$INSTALL_DIR/requirements.txt" ]; then
    $INSTALL_DIR/venv/bin/pip install -r $INSTALL_DIR/requirements.txt
else
    echo -e "${YELLOW}⚠️ Geen requirements bestand gevonden, essentiële pakketten worden handmatig geïnstalleerd${NC}"
    $INSTALL_DIR/venv/bin/pip install flask flask-login flask-sqlalchemy flask-wtf flask-migrate
    $INSTALL_DIR/venv/bin/pip install python-dotenv sqlalchemy apscheduler boto3 requests
    $INSTALL_DIR/venv/bin/pip install trafilatura psycopg2-binary werkzeug gunicorn
    $INSTALL_DIR/venv/bin/pip install email-validator wtforms psutil
fi

# Zorg dat gunicorn en psycopg2 zeker geïnstalleerd zijn
$INSTALL_DIR/venv/bin/pip install --upgrade gunicorn psycopg2-binary

echo -e "${GREEN}✓ Python omgeving en pakketten geïnstalleerd${NC}"

# 8. Configuratiebestand aanmaken
echo -e "${GREEN}Stap 8: Configuratiebestand aanmaken...${NC}"

# Genereer secret key
SECRET_KEY=$(openssl rand -hex 24)

# Maak .env bestand
cat > $INSTALL_DIR/.env << EOF
FLASK_APP=main.py
FLASK_ENV=production
DATABASE_URL=postgresql://radiologger:$DB_PASSWORD@localhost:5432/radiologger
FLASK_SECRET_KEY=$SECRET_KEY

# Mappen configuratie
RECORDINGS_DIR=$RECORDINGS_DIR
LOGS_DIR=$LOG_DIR
RETENTION_DAYS=30
LOCAL_FILE_RETENTION=0

# API endpoints
OMROEP_LVC_URL=https://gemist.omroeplvc.nl/
DENNIS_API_URL=https://logger.dennishoogeveenmedia.nl/api/stations.json

# Systeem configuratie
FFMPEG_PATH=/usr/bin/ffmpeg

# S3 storage configuratie - later in te stellen via de setup interface
WASABI_ACCESS_KEY=
WASABI_SECRET_KEY=
WASABI_BUCKET=
WASABI_REGION=eu-central-1
WASABI_ENDPOINT_URL=https://s3.eu-central-1.wasabisys.com
EOF

# Stel permissies in
chown radiologger:radiologger $INSTALL_DIR/.env
chmod 600 $INSTALL_DIR/.env

echo -e "${GREEN}✓ Configuratiebestand aangemaakt${NC}"

# 9. Systemd service instellen
echo -e "${GREEN}Stap 9: Systemd service instellen...${NC}"

cat > /etc/systemd/system/radiologger.service << EOF
[Unit]
Description=Radiologger Web Application
After=network.target postgresql.service

[Service]
User=radiologger
Group=radiologger
WorkingDirectory=$INSTALL_DIR
Environment="HOME=$INSTALL_DIR"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --workers 4 --bind 0.0.0.0:5000 --access-logfile $LOG_DIR/access.log --error-logfile $LOG_DIR/error.log main:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable radiologger
echo -e "${GREEN}✓ Systemd service ingesteld${NC}"

# 10. Nginx configureren
echo -e "${GREEN}Stap 10: Nginx configureren...${NC}"

cat > /etc/nginx/sites-available/radiologger << EOF
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/radiologger_access.log;
    error_log /var/log/nginx/radiologger_error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Enable site en verwijder default config
ln -sf /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo -e "${GREEN}✓ Nginx geconfigureerd${NC}"

# 11. Services starten
echo -e "${GREEN}Stap 11: Services starten...${NC}"
systemctl start radiologger
systemctl restart nginx
echo -e "${GREEN}✓ Services gestart${NC}"

# 12. Fix permissions script aanmaken
echo -e "${GREEN}Stap 12: Fixing permissions script aanmaken...${NC}"

cat > $INSTALL_DIR/fix_permissions.sh << 'EOF'
#!/bin/bash
# Fix permissions script voor Radiologger
set -e

if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd!"
   exit 1
fi

INSTALL_DIR="/opt/radiologger"
LOG_DIR="/var/log/radiologger"
RECORDINGS_DIR="/var/lib/radiologger/recordings"

echo "Radiologger permissies fixen..."

# Fix permissies
chown -R radiologger:radiologger $INSTALL_DIR
chown -R radiologger:radiologger $LOG_DIR
chown -R radiologger:radiologger $RECORDINGS_DIR

chmod -R 755 $INSTALL_DIR
chmod -R 755 $LOG_DIR
chmod -R 755 $RECORDINGS_DIR

# Fix .env bestand
if [ -f "$INSTALL_DIR/.env" ]; then
    chmod 600 $INSTALL_DIR/.env
    chown radiologger:radiologger $INSTALL_DIR/.env
    echo "✓ .env bestandsrechten ingesteld"
fi

# Fix systemd service
if [ -f "/etc/systemd/system/radiologger.service" ]; then
    # Controleer of HOME environment is ingesteld
    if ! grep -q "Environment=\"HOME=$INSTALL_DIR\"" /etc/systemd/system/radiologger.service; then
        echo "HOME environment toevoegen aan service..."
        sed -i "/\[Service\]/a Environment=\"HOME=$INSTALL_DIR\"" /etc/systemd/system/radiologger.service
        systemctl daemon-reload
    fi
    
    # Controleer of EnvironmentFile is ingesteld
    if ! grep -q "EnvironmentFile=$INSTALL_DIR/.env" /etc/systemd/system/radiologger.service; then
        echo "EnvironmentFile toevoegen aan service..."
        sed -i "/\[Service\]/a EnvironmentFile=$INSTALL_DIR/.env" /etc/systemd/system/radiologger.service
        systemctl daemon-reload
    fi
    
    echo "✓ Systemd service geconfigureerd"
fi

# Services herstarten
systemctl restart radiologger
systemctl restart nginx

echo "✓ Permissies succesvol ingesteld en services herstart!"
EOF

chmod +x $INSTALL_DIR/fix_permissions.sh
chown radiologger:radiologger $INSTALL_DIR/fix_permissions.sh

echo -e "${GREEN}✓ Fix permissions script aangemaakt${NC}"

# 13. Diagnose script aanmaken
echo -e "${GREEN}Stap 13: Diagnose script aanmaken...${NC}"

cat > $INSTALL_DIR/diagnose_502.sh << 'EOF'
#!/bin/bash
# Diagnose script voor 502 Bad Gateway in Radiologger
set -e

if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd!"
   exit 1
fi

echo "Radiologger 502 diagnose script..."

# Check service status
echo "1. Controleren service status..."
systemctl status radiologger --no-pager

# Check if service is running on port 5000
echo "2. Controleren of service draait op poort 5000..."
if netstat -tuln | grep -q ":5000 "; then
    echo "✓ Service draait op poort 5000"
else
    echo "✗ Geen service gevonden op poort 5000!"
fi

# Check logs
echo "3. Controleren service logs..."
journalctl -u radiologger --no-pager -n 20

# Check nginx logs
echo "4. Controleren nginx error logs..."
tail -n 20 /var/log/nginx/radiologger_error.log

# Check main.py
echo "5. Controleren of main.py bestaat..."
if [ -f "/opt/radiologger/main.py" ]; then
    echo "✓ main.py bestaat"
else
    echo "✗ main.py bestaat niet! Dit is essentieel voor de werking van gunicorn"
fi

# Check app.py
echo "6. Controleren of app.py bestaat..."
if [ -f "/opt/radiologger/app.py" ]; then
    echo "✓ app.py bestaat"
else
    echo "✗ app.py bestaat niet! Dit is essentieel voor Flask"
fi

# Run fix_permissions.sh
echo "7. Permissies repareren..."
bash /opt/radiologger/fix_permissions.sh

# Restart services
echo "8. Services herstarten..."
systemctl restart radiologger
systemctl restart nginx

echo "Diagnose voltooid. Controleer nu of de 502 error is verholpen."
EOF

chmod +x $INSTALL_DIR/diagnose_502.sh
chown radiologger:radiologger $INSTALL_DIR/diagnose_502.sh

echo -e "${GREEN}✓ Diagnose script aangemaakt${NC}"

# 14. Installatie voltooien
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}           INSTALLATIE VOLTOOID!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""
echo "De Radiologger is succesvol geïnstalleerd op je systeem."
echo ""
echo "Website URL: http://$(hostname -I | awk '{print $1}')"
echo "Database gebruiker: radiologger"
echo "Database wachtwoord: $DB_PASSWORD"
echo ""
echo "Mocht je toch problemen ondervinden, dan kun je de volgende"
echo "diagnose-scripts gebruiken:"
echo ""
echo "- sudo bash $INSTALL_DIR/fix_permissions.sh"
echo "- sudo bash $INSTALL_DIR/diagnose_502.sh"
echo ""
echo "Succes met het gebruik van Radiologger!"