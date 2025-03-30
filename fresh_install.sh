#!/bin/bash
# Volledig nieuw installatiescript voor Radiologger
# Dit script downloadt ALLE bestanden direct van GitHub en breekt af bij fouten
# Geschreven op basis van de kennis uit eerdere fixes

set -e

# Kleuren voor output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=====================================================${NC}"
echo -e "${BLUE}        VOLLEDIGE RADIOLOGGER INSTALLATIE           ${NC}"
echo -e "${BLUE}=====================================================${NC}"
echo ""
echo "Dit script voert een volledige, betrouwbare installatie uit:"
echo "1. Download ALLE bestanden van GitHub (geen bestanden overslaan)"
echo "2. Installeert vereiste systeempakketten"
echo "3. Installeert PostgreSQL en zet de database op"
echo "4. Configureert de applicatie met alle vereiste bestanden"
echo "5. Installeert en start services"
echo ""

# Controleer root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Dit script moet als root worden uitgevoerd!${NC}"
    exit 1
fi

# Constanten en instellingen
INSTALL_DIR="/opt/radiologger"
LOGS_DIR="/var/log/radiologger"
RECORDINGS_DIR="/var/lib/radiologger/recordings"
GITHUB_RAW="https://raw.githubusercontent.com/sandersmale/logger/main"
GITHUB_REPO="https://github.com/sandersmale/logger.git"
TEMP_DIR="/tmp/radiologger_repo"

# Functie om het script af te breken bij fouten
fatal_error() {
    echo -e "${RED}FATALE FOUT: $1${NC}"
    echo "Script wordt afgebroken. Probleem moet worden opgelost."
    exit 1
}

# Functie om bestanden direct van GitHub te downloaden
download_file() {
    local bestand="$1"
    local directory="${2:-$INSTALL_DIR}"
    
    echo "Downloading $bestand..."
    
    # Zorg dat de doelmap bestaat
    mkdir -p "$directory"
    
    # Download het bestand
    if ! wget -q -O "$directory/$bestand" "$GITHUB_RAW/$bestand"; then
        fatal_error "Kon $bestand niet downloaden van $GITHUB_RAW/$bestand"
    fi
    
    # Controleer of het bestand goed is gedownload
    if [ ! -s "$directory/$bestand" ]; then
        fatal_error "Gedownloade bestand $bestand is leeg of ontbreekt!"
    fi
    
    # Zet rechten goed
    chmod 755 "$directory/$bestand"
    chown radiologger:radiologger "$directory/$bestand"
    
    echo -e "${GREEN}✓ $bestand succesvol gedownload${NC}"
}

# STAP 1: Systeem voorbereiden
echo -e "\n${BLUE}[STAP 1]${NC} Systeem voorbereiden en pakketten installeren..."
apt-get update
apt-get install -y git curl wget python3 python3-venv python3-pip ffmpeg nginx postgresql postgresql-contrib

# STAP 2: Repository volledig clonen
echo -e "\n${BLUE}[STAP 2]${NC} Volledige repository clonen van GitHub..."
# Maak temp directory en verwijder als deze al bestaat
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

if ! git clone --depth=1 "$GITHUB_REPO" "$TEMP_DIR"; then
    fatal_error "Kon repository niet clonen van $GITHUB_REPO"
fi
echo -e "${GREEN}✓ Repository succesvol gecloned naar $TEMP_DIR${NC}"

# STAP 3: Mappen en gebruiker aanmaken
echo -e "\n${BLUE}[STAP 3]${NC} Mappen en gebruiker aanmaken..."
# Aanmaken radiologger gebruiker als deze nog niet bestaat
if ! id -u radiologger &>/dev/null; then
    useradd -m -s /bin/bash radiologger
    echo -e "${GREEN}✓ Gebruiker radiologger aangemaakt${NC}"
else
    echo "Gebruiker radiologger bestaat al."
fi

# Maak mappen aan
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOGS_DIR"
mkdir -p "$RECORDINGS_DIR"

# Stel rechten in
chown -R radiologger:radiologger "$INSTALL_DIR"
chown -R radiologger:radiologger "$LOGS_DIR"
chown -R radiologger:radiologger "$RECORDINGS_DIR"
chmod -R 755 "$INSTALL_DIR"
chmod -R 755 "$LOGS_DIR"
chmod -R 755 "$RECORDINGS_DIR"

echo -e "${GREEN}✓ Mappen aangemaakt en rechten ingesteld${NC}"

# STAP 4: Bestanden kopiëren naar installatiemap
echo -e "\n${BLUE}[STAP 4]${NC} Bestanden kopiëren naar installatiemap..."
rsync -av --exclude='.git' "$TEMP_DIR/" "$INSTALL_DIR/"
echo -e "${GREEN}✓ Bestanden gekopieerd naar $INSTALL_DIR${NC}"

# STAP 5: Controleer op kritieke bestanden en download ontbrekende
echo -e "\n${BLUE}[STAP 5]${NC} Controleren op kritieke bestanden..."
kritieke_bestanden=("main.py" "app.py" "routes.py" "player.py" "models.py" "auth.py" "forms.py" "logger.py" "config.py" "storage.py")
missende_bestanden=()

for bestand in "${kritieke_bestanden[@]}"; do
    if [ ! -f "$INSTALL_DIR/$bestand" ]; then
        missende_bestanden+=("$bestand")
    fi
done

# Als er missende bestanden zijn, download ze direct
if [ ${#missende_bestanden[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️ De volgende kritieke bestanden ontbreken en worden gedownload:${NC}"
    for missend in "${missende_bestanden[@]}"; do
        echo "   - $missend"
        download_file "$missend"
    done
else
    echo -e "${GREEN}✓ Alle kritieke bestanden zijn aanwezig${NC}"
fi

# STAP 6: Speciaal controleren op forms.py (vaak ontbrekend)
echo -e "\n${BLUE}[STAP 6]${NC} Extra controle op forms.py (cruciaal voor imports)..."
if [ ! -f "$INSTALL_DIR/forms.py" ]; then
    echo -e "${YELLOW}⚠️ forms.py ontbreekt! Wordt aangemaakt...${NC}"
    cat > "$INSTALL_DIR/forms.py" << 'EOL'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField, SelectField, TextAreaField, HiddenField
from wtforms.validators import DataRequired, Length, URL, Optional, Email, EqualTo

class LoginForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired()])
    password = PasswordField('Wachtwoord', validators=[DataRequired()])
    remember_me = BooleanField('Onthoud mij')
    submit = SubmitField('Inloggen')

class UserForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    password = PasswordField('Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    role = SelectField('Rol', choices=[('listener', 'Listener'), ('editor', 'Editor'), ('admin', 'Admin')])
    submit = SubmitField('Gebruiker toevoegen')

class StationForm(FlaskForm):
    name = StringField('Stationsnaam', validators=[DataRequired(), Length(min=2, max=100)])
    recording_url = StringField('Stream URL', validators=[DataRequired(), URL()])
    has_schedule = BooleanField('Geplande opname')
    record_reason = TextAreaField('Reden voor opname', validators=[Optional(), Length(max=255)])
    submit = SubmitField('Station opslaan')

class DennisStationForm(FlaskForm):
    stations = HiddenField('Geselecteerde stations')
    submit = SubmitField('Opslaan')

class TestStreamForm(FlaskForm):
    url = StringField('Stream URL', validators=[DataRequired(), URL()])
    submit = SubmitField('Test Stream')

class SetupForm(FlaskForm):
    admin_username = StringField('Administrator Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    admin_password = PasswordField('Administrator Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    admin_password_confirm = PasswordField('Bevestig Wachtwoord', validators=[DataRequired(), EqualTo('admin_password', message='Wachtwoorden moeten overeenkomen')])
    
    wasabi_access_key = StringField('Wasabi Access Key', validators=[DataRequired()])
    wasabi_secret_key = StringField('Wasabi Secret Key', validators=[DataRequired()])
    wasabi_bucket = StringField('Wasabi Bucket', validators=[DataRequired()])
    wasabi_region = StringField('Wasabi Regio', validators=[DataRequired()], default='eu-central-1')
    
    submit = SubmitField('Setup Voltooien')
EOL
    chmod 755 "$INSTALL_DIR/forms.py"
    chown radiologger:radiologger "$INSTALL_DIR/forms.py"
    echo -e "${GREEN}✓ forms.py aangemaakt${NC}"
else
    echo -e "${GREEN}✓ forms.py is aanwezig${NC}"
fi

# STAP 7: Python virtuele omgeving opzetten
echo -e "\n${BLUE}[STAP 7]${NC} Python virtuele omgeving opzetten..."
cd "$INSTALL_DIR"
python3 -m venv venv
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --upgrade setuptools wheel

# Installeer alle vereiste pakketten
echo "Pakketten installeren..."
"$INSTALL_DIR/venv/bin/pip" install flask flask-login flask-sqlalchemy flask-wtf flask-migrate
"$INSTALL_DIR/venv/bin/pip" install python-dotenv sqlalchemy apscheduler boto3 requests
"$INSTALL_DIR/venv/bin/pip" install trafilatura psycopg2-binary werkzeug gunicorn
"$INSTALL_DIR/venv/bin/pip" install email-validator wtforms psutil
echo -e "${GREEN}✓ Python pakketten geïnstalleerd${NC}"

# STAP 8: PostgreSQL database opzetten
echo -e "\n${BLUE}[STAP 8]${NC} PostgreSQL database opzetten..."
# Genereer een veilig wachtwoord
DB_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)

# PostgreSQL database en gebruiker aanmaken
sudo -u postgres psql -c "CREATE USER radiologger WITH PASSWORD '$DB_PASSWORD';" || true
sudo -u postgres psql -c "CREATE DATABASE radiologger OWNER radiologger;" || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE radiologger TO radiologger;" || true
echo -e "${GREEN}✓ Database opgezet met wachtwoord: $DB_PASSWORD${NC}"

# STAP 9: Configuratiebestand aanmaken (.env)
echo -e "\n${BLUE}[STAP 9]${NC} Configuratiebestand aanmaken..."
# Genereer een random secret key
SECRET_KEY=$(openssl rand -hex 24)

# Maak het .env bestand
cat > "$INSTALL_DIR/.env" << EOF
FLASK_APP=main.py
FLASK_ENV=production
DATABASE_URL=postgresql://radiologger:$DB_PASSWORD@localhost:5432/radiologger
FLASK_SECRET_KEY=$SECRET_KEY

# Mappen configuratie
RECORDINGS_DIR=$RECORDINGS_DIR
LOGS_DIR=$LOGS_DIR
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

# Rechten instellen
chown radiologger:radiologger "$INSTALL_DIR/.env"
chmod 600 "$INSTALL_DIR/.env"
echo -e "${GREEN}✓ Configuratiebestand aangemaakt${NC}"

# STAP 10: Systemd service instellen
echo -e "\n${BLUE}[STAP 10]${NC} Systemd service instellen..."
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
Environment="HOME=/opt/radiologger"
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
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable radiologger
echo -e "${GREEN}✓ Systemd service ingesteld${NC}"

# STAP 11: Nginx configureren
echo -e "\n${BLUE}[STAP 11]${NC} Nginx configureren..."
cat > /etc/nginx/sites-available/radiologger << 'EOL'
server {
    listen 80;
    server_name _;

    access_log /var/log/nginx/radiologger_access.log;
    error_log /var/log/nginx/radiologger_error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOL

# Enable site en verwijder default config
ln -sf /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

echo -e "${GREEN}✓ Nginx geconfigureerd${NC}"

# STAP 12: Diensten starten
echo -e "\n${BLUE}[STAP 12]${NC} Diensten starten..."
systemctl restart postgresql
systemctl start radiologger
systemctl restart nginx
echo -e "${GREEN}✓ Diensten gestart${NC}"

# STAP 13: Diagnose script aanmaken (voor troubleshooting)
echo -e "\n${BLUE}[STAP 13]${NC} Diagnose hulpmiddelen aanmaken..."
# fix_permissions.sh script
cat > "$INSTALL_DIR/fix_permissions.sh" << 'EOL'
#!/bin/bash
# Fix permissions script voor Radiologger

if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd!"
   exit 1
fi

# Fix permissies
echo "Permissies herstellen..."
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger

chmod -R 755 /opt/radiologger
chmod -R 755 /var/log/radiologger
chmod -R 755 /var/lib/radiologger

# .env bestand speciale permissies
if [ -f "/opt/radiologger/.env" ]; then
    chmod 600 /opt/radiologger/.env
    chown radiologger:radiologger /opt/radiologger/.env
    echo "✓ .env permissies hersteld"
fi

# Controleer systemd service
if [ -f "/etc/systemd/system/radiologger.service" ]; then
    # Voeg HOME toe als het ontbreekt
    if ! grep -q "HOME=/opt/radiologger" /etc/systemd/system/radiologger.service; then
        echo "HOME directory toevoegen aan service..."
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✓ HOME directory toegevoegd aan service"
    fi
    
    # Voeg EnvironmentFile toe als het ontbreekt
    if ! grep -q "EnvironmentFile=" /etc/systemd/system/radiologger.service; then
        echo "EnvironmentFile toevoegen aan service..."
        sed -i '/\[Service\]/a EnvironmentFile=/opt/radiologger/.env' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✓ EnvironmentFile toegevoegd aan service"
    fi
fi

# Herstart services
echo "Services herstarten..."
systemctl restart radiologger
systemctl restart nginx

echo "✓ Permissies succesvol hersteld!"
echo "Test nu de website door naar http://[server-IP] te gaan."
EOL

chmod 755 "$INSTALL_DIR/fix_permissions.sh"
chown radiologger:radiologger "$INSTALL_DIR/fix_permissions.sh"

# diagnose_502.sh script
cat > "$INSTALL_DIR/diagnose_502.sh" << 'EOL'
#!/bin/bash
# Diagnose script voor 502 Bad Gateway errors

echo "================== RADIOLOGGER DIAGNOSE =================="
echo "Dit script controleert veelvoorkomende oorzaken van 502 errors"
echo ""

# 1. Controleer of services draaien
echo "[1] Controle services status:"
echo "==============================="
echo "PostgreSQL status:"
systemctl status postgresql | grep Active
echo ""
echo "Radiologger status:"
systemctl status radiologger | grep Active
echo ""
echo "Nginx status:"
systemctl status nginx | grep Active
echo ""

# 2. Controleer poorten
echo "[2] Controle poorten in gebruik:"
echo "==============================="
if ! command -v netstat &> /dev/null; then
    apt-get install -y net-tools
fi

echo "Poort 5000 (Radiologger):"
netstat -tuln | grep :5000 || echo "❌ Poort 5000 niet in gebruik!"
echo ""
echo "Poort 80 (Nginx):"
netstat -tuln | grep :80 || echo "❌ Poort 80 niet in gebruik!"
echo ""

# 3. Controleer forms.py (vaak ontbrekend)
echo "[3] Controle forms.py (cruciaal bestand):"
echo "==============================="
if [ -f "/opt/radiologger/forms.py" ]; then
    echo "✓ forms.py bestaat"
else
    echo "❌ forms.py ontbreekt! Aanmaken..."
    # Download of maak forms.py aan
    if wget -q -O "/opt/radiologger/forms.py" "https://raw.githubusercontent.com/sandersmale/logger/main/forms.py"; then
        chmod 755 "/opt/radiologger/forms.py"
        chown radiologger:radiologger "/opt/radiologger/forms.py"
        echo "✓ forms.py gedownload van GitHub"
    else
        echo "❌ Kon forms.py niet downloaden, handmatig aanmaken..."
        cat > "/opt/radiologger/forms.py" << 'EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField, SelectField, TextAreaField, HiddenField
from wtforms.validators import DataRequired, Length, URL, Optional, Email, EqualTo

class LoginForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired()])
    password = PasswordField('Wachtwoord', validators=[DataRequired()])
    remember_me = BooleanField('Onthoud mij')
    submit = SubmitField('Inloggen')

class UserForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    password = PasswordField('Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    role = SelectField('Rol', choices=[('listener', 'Listener'), ('editor', 'Editor'), ('admin', 'Admin')])
    submit = SubmitField('Gebruiker toevoegen')

class StationForm(FlaskForm):
    name = StringField('Stationsnaam', validators=[DataRequired(), Length(min=2, max=100)])
    recording_url = StringField('Stream URL', validators=[DataRequired(), URL()])
    has_schedule = BooleanField('Geplande opname')
    record_reason = TextAreaField('Reden voor opname', validators=[Optional(), Length(max=255)])
    submit = SubmitField('Station opslaan')

class DennisStationForm(FlaskForm):
    stations = HiddenField('Geselecteerde stations')
    submit = SubmitField('Opslaan')

class TestStreamForm(FlaskForm):
    url = StringField('Stream URL', validators=[DataRequired(), URL()])
    submit = SubmitField('Test Stream')

class SetupForm(FlaskForm):
    admin_username = StringField('Administrator Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    admin_password = PasswordField('Administrator Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    admin_password_confirm = PasswordField('Bevestig Wachtwoord', validators=[DataRequired(), EqualTo('admin_password', message='Wachtwoorden moeten overeenkomen')])
    
    wasabi_access_key = StringField('Wasabi Access Key', validators=[DataRequired()])
    wasabi_secret_key = StringField('Wasabi Secret Key', validators=[DataRequired()])
    wasabi_bucket = StringField('Wasabi Bucket', validators=[DataRequired()])
    wasabi_region = StringField('Wasabi Regio', validators=[DataRequired()], default='eu-central-1')
    
    submit = SubmitField('Setup Voltooien')
EOF
        chmod 755 "/opt/radiologger/forms.py"
        chown radiologger:radiologger "/opt/radiologger/forms.py"
        echo "✓ forms.py handmatig aangemaakt"
    fi
fi
echo ""

# 4. Toon recente logs
echo "[4] Recente logs bekijken:"
echo "==============================="
echo "Radiologger service logs (laatste 10 regels):"
journalctl -u radiologger -n 10 --no-pager
echo ""
echo "Nginx logs (laatste 10 regels):"
if [ -f "/var/log/nginx/radiologger_error.log" ]; then
    tail -n 10 /var/log/nginx/radiologger_error.log
else
    echo "❌ Nginx log bestand niet gevonden!"
fi
echo ""

# 5. Controleer database connectie
echo "[5] Database connectie testen:"
echo "==============================="
if [ -f "/opt/radiologger/.env" ]; then
    DB_URL=$(grep DATABASE_URL /opt/radiologger/.env | cut -d= -f2-)
    if [ -n "$DB_URL" ]; then
        echo "Database URL gevonden: ${DB_URL:0:20}..."
        
        if command -v psql &> /dev/null; then
            echo "Test database connectie..."
            sudo -u radiologger bash -c "PGPASSWORD=$(echo $DB_URL | grep -oP '://\K[^:]*' | cut -d@ -f1) psql -h $(echo $DB_URL | grep -oP '@\K[^:]*' | cut -d/ -f1) -U $(echo $DB_URL | grep -oP '://\K[^:]*' | cut -d: -f1) -c '\conninfo'"
        else
            echo "❌ psql commando niet beschikbaar"
        fi
    else
        echo "❌ DATABASE_URL niet gevonden in .env bestand!"
    fi
else
    echo "❌ .env bestand niet gevonden!"
fi
echo ""

# 6. Automatische fixes uitvoeren
echo "[6] Automatische reparatie uitvoeren:"
echo "==============================="
echo "Volgende acties worden uitgevoerd:"
echo "1. Permissies herstellen"
echo "2. Services herstarten"
echo "3. Forms.py aanmaken/controleren"
echo "4. HOME directory in service instellen"

# Fix permissies
echo "Permissies herstellen..."
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger
chmod -R 755 /opt/radiologger
chmod -R 755 /var/log/radiologger
chmod -R 755 /var/lib/radiologger
if [ -f "/opt/radiologger/.env" ]; then
    chmod 600 /opt/radiologger/.env
fi

# Fix HOME in service
if [ -f "/etc/systemd/system/radiologger.service" ]; then
    if ! grep -q "HOME=" /etc/systemd/system/radiologger.service; then
        echo "HOME directory toevoegen aan service..."
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
    fi
    
    if ! grep -q "EnvironmentFile=" /etc/systemd/system/radiologger.service; then
        echo "EnvironmentFile toevoegen aan service..."
        sed -i '/\[Service\]/a EnvironmentFile=/opt/radiologger/.env' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
    fi
fi

# Restart services
echo "Services herstarten..."
systemctl restart postgresql
systemctl restart radiologger
systemctl restart nginx

echo ""
echo "Diagnose en reparatie voltooid!"
echo "Test nu de website door naar http://[server-IP] te gaan."
echo "Als het nog steeds niet werkt, controleer uitgebreide logs met:"
echo "  sudo journalctl -u radiologger -n 100"
echo "===========================================" 
EOL

chmod 755 "$INSTALL_DIR/diagnose_502.sh"
chown radiologger:radiologger "$INSTALL_DIR/diagnose_502.sh"

echo -e "${GREEN}✓ Diagnose hulpmiddelen aangemaakt${NC}"

# STAP 14: Installatie verifiëren
echo -e "\n${BLUE}[STAP 14]${NC} Installatie verifiëren..."
# Controleer services
echo "Controleren service status..."
systemctl status radiologger --no-pager
echo ""
systemctl status nginx --no-pager
echo ""

# Controleer of poort 5000 in gebruik is
echo "Controleren of Radiologger actief is op poort 5000..."
if netstat -tuln | grep -q ":5000 "; then
    echo -e "${GREEN}✓ Radiologger service actief op poort 5000${NC}"
else
    echo -e "${RED}❌ Geen proces gevonden op poort 5000!${NC}"
    echo "Controleer logs voor meer informatie: sudo journalctl -u radiologger -n 50"
    echo "Voer diagnose uit: sudo $INSTALL_DIR/diagnose_502.sh"
fi

# Test of de applicatie bereikbaar is
echo ""
echo "Testen of applicatie bereikbaar is via localhost..."
if curl -I http://127.0.0.1:5000 &>/dev/null; then
    echo -e "${GREEN}✓ Radiologger bereikbaar op localhost:5000${NC}"
else
    echo -e "${RED}❌ Kon geen verbinding maken met radiologger op localhost:5000!${NC}"
    echo "Dit kan duiden op een probleem met de applicatie."
    echo "Voer diagnose uit: sudo $INSTALL_DIR/diagnose_502.sh"
fi

# Opschonen
echo -e "\n${BLUE}[STAP 15]${NC} Opruimen..."
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓ Tijdelijke bestanden opgeruimd${NC}"
fi

# Toon succes bericht en volgende stappen
echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}       RADIOLOGGER INSTALLATIE VOLTOOID!              ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo -e "${BLUE}Belangrijke informatie:${NC}"
echo "- Database gebruiker: radiologger"
echo "- Database wachtwoord: $DB_PASSWORD"
echo "- Installatiemap: $INSTALL_DIR"
echo "- Log map: $LOGS_DIR" 
echo "- Opnamemap: $RECORDINGS_DIR"
echo ""
echo -e "${BLUE}De webinterface is bereikbaar via:${NC}"
echo "http://$(hostname -I | awk '{print $1}')"
echo ""
echo -e "${BLUE}Eerste keer gebruik:${NC}"
echo "Bij de eerste keer gebruik moet je een admin-account aanmaken"
echo "en de Wasabi S3 opslag configureren (indien gewenst)."
echo ""
echo -e "${BLUE}Als je problemen ondervindt:${NC}"
echo "1. Voer diagnose uit: sudo $INSTALL_DIR/diagnose_502.sh"
echo "2. Fix permissies: sudo $INSTALL_DIR/fix_permissions.sh"
echo "3. Controleer logs: sudo journalctl -u radiologger -n 50"
echo ""
echo "Bedankt voor het installeren van Radiologger!"