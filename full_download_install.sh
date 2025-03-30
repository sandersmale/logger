#!/bin/bash
# Radiologger volledige downloadinstallatie
# Dit script downloadt eerst de volledige repository en voert daarna de installatie uit
# Alle bestanden zijn dan gegarandeerd aanwezig

set -e

# Kleuren voor output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}     RADIOLOGGER VOLLEDIGE INSTALLATIE        ${NC}"
echo -e "${BLUE}===============================================${NC}"
echo ""
echo "Dit script voert een volledige installatie uit van Radiologger:"
echo "1. Download de volledige code van GitHub"
echo "2. Installeert alle noodzakelijke systeempakketten"
echo "3. Configureert de database en gebruikers"
echo "4. Installeert en configureert de applicatie"
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Dit script moet als root worden uitgevoerd (sudo).${NC}"
   exit 1
fi

# Controleer essentiële tools
echo "Controleren of essentiële tools geïnstalleerd zijn..."
for tool in git curl wget; do
    if ! command -v $tool &> /dev/null; then
        echo -e "${YELLOW}$tool is niet geïnstalleerd. Installeren...${NC}"
        apt-get update && apt-get install -y $tool
    fi
done

# Constante variabelen
REPO_URL="https://github.com/sandersmale/logger.git"
INSTALL_DIR="/opt/radiologger"
BACKUP_DIR="/opt/radiologger_backup_$(date +%Y%m%d_%H%M%S)"
TEMP_DIR="/tmp/radiologger_repo"

# Stap 1: Maak een backup van een bestaande installatie
echo -e "\n${BLUE}[Stap 1]${NC} Controle bestaande installatie"
if [ -d "$INSTALL_DIR" ]; then
    echo "Bestaande installatie gevonden. Backup maken..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$INSTALL_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
    echo -e "${GREEN}✓ Backup gemaakt naar $BACKUP_DIR${NC}"
    
    echo "Vraag: Wil je de bestaande installatie behouden of alles verwijderen en opnieuw beginnen?"
    echo "1) Behouden - voeg alleen ontbrekende bestanden toe (veiliger)"
    echo "2) Verwijderen - start helemaal opnieuw (schoner)"
    read -p "Keuze (1/2): " reinstall_choice
    
    if [ "$reinstall_choice" = "2" ]; then
        echo "Je hebt gekozen om opnieuw te beginnen. Bestaande installatie verwijderen..."
        rm -rf "$INSTALL_DIR"/*
        echo -e "${GREEN}✓ Bestaande installatie verwijderd${NC}"
    fi
else
    echo "Geen bestaande installatie gevonden. Nieuwe installatie wordt uitgevoerd."
    mkdir -p "$INSTALL_DIR"
fi

# Stap 2: Download de volledige repository van GitHub
echo -e "\n${BLUE}[Stap 2]${NC} Downloaden van volledige repository van GitHub"
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

echo "Repository klonen van $REPO_URL..."
git clone --depth=1 "$REPO_URL" "$TEMP_DIR"
echo -e "${GREEN}✓ Repository succesvol gedownload${NC}"

# Stap 3: Kopieer alle bestanden naar de installatiemap
echo -e "\n${BLUE}[Stap 3]${NC} Bestanden kopiëren naar installatiemap"
rsync -av --exclude='.git*' "$TEMP_DIR"/ "$INSTALL_DIR"/
chown -R root:root "$INSTALL_DIR"
echo -e "${GREEN}✓ Alle bestanden gekopieerd naar $INSTALL_DIR${NC}"

# Stap 4: Installeer de radiologger gebruiker als deze nog niet bestaat
echo -e "\n${BLUE}[Stap 4]${NC} Radiologger gebruiker configureren"
if id "radiologger" &>/dev/null; then
    echo "Gebruiker radiologger bestaat al."
else
    useradd -m -s /bin/bash radiologger
    echo -e "${GREEN}✓ Gebruiker radiologger aangemaakt${NC}"
fi

# Stap 5: Benodigde mappen aanmaken en rechten instellen
echo -e "\n${BLUE}[Stap 5]${NC} Benodigde mappen aanmaken"
mkdir -p /var/log/radiologger
mkdir -p /var/lib/radiologger/recordings
chown -R radiologger:radiologger "$INSTALL_DIR"
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger
chmod -R 755 "$INSTALL_DIR"
chmod -R 755 /var/log/radiologger
chmod -R 755 /var/lib/radiologger

echo -e "${GREEN}✓ Mappen aangemaakt en rechten ingesteld${NC}"

# Stap 6: Voer het installatiescript uit indien aanwezig, maar met aangepaste parameters
echo -e "\n${BLUE}[Stap 6]${NC} Installatiescript uitvoeren"
cd "$INSTALL_DIR"

# Maak het originele installatiescript uitvoerbaar
if [ -f "install.sh" ]; then
    chmod +x install.sh
    echo "Aangepaste installatie uitvoeren met gedownloade bestanden..."
    
    # Stel enkele variabelen in vóór uitvoering van install.sh
    export RADIOLOGGER_SKIP_DOWNLOAD=true  # Geef aan dat bestanden al aanwezig zijn
    export RADIOLOGGER_TEMP_DIR="$TEMP_DIR"
    
    # Voer het script uit met automatische antwoorden
    ./install.sh
else
    echo -e "${RED}Het install.sh script is niet gevonden in de repository!${NC}"
    echo "Dit is onverwacht. Controleer de GitHub repository."
    exit 1
fi

# Stap 7: Controleer of alle kritieke bestanden aanwezig zijn
echo -e "\n${BLUE}[Stap 7]${NC} Controleren of alle kritieke bestanden aanwezig zijn"
kritieke_bestanden=("main.py" "app.py" "routes.py" "player.py" "models.py" "auth.py" "config.py" "storage.py" "forms.py" "logger.py")
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
    
    echo ""
    echo -e "${YELLOW}Probeer deze bestanden opnieuw van GitHub te downloaden...${NC}"
    
    for missend in "${missende_bestanden[@]}"; do
        echo "Downloaden van $missend..."
        if wget -q -O "$INSTALL_DIR/$missend" "https://raw.githubusercontent.com/sandersmale/logger/main/$missend"; then
            chmod 755 "$INSTALL_DIR/$missend"
            chown radiologger:radiologger "$INSTALL_DIR/$missend"
            echo -e "${GREEN}✓ $missend succesvol gedownload${NC}"
        else
            echo -e "${RED}❌ Kon $missend niet downloaden${NC}"
        fi
    done
else
    echo -e "${GREEN}✓ Alle kritieke bestanden zijn aanwezig${NC}"
fi

# Stap 8: Fix specifieke importproblemen als forms.py ontbreekt
if [[ " ${missende_bestanden[*]} " =~ " forms.py " ]]; then
    echo -e "\n${BLUE}[Stap 8]${NC} forms.py ontbreekt nog steeds, creëer een noodversie"
    
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
    echo -e "${GREEN}✓ forms.py succesvol aangemaakt${NC}"
fi

# Stap 9: Controleer en installeer Python modules
echo -e "\n${BLUE}[Stap 9]${NC} Controleren of Python modules correct zijn geïnstalleerd"
cd "$INSTALL_DIR"
if [ -d "venv" ]; then
    echo "Virtual environment gevonden, controleren op belangrijke modules..."
    
    # Controleer of flask-wtf is geïnstalleerd, wat essentieel is voor forms.py
    if ! "$INSTALL_DIR/venv/bin/pip" show flask-wtf &>/dev/null; then
        echo -e "${YELLOW}flask-wtf is niet geïnstalleerd. Installeren...${NC}"
        "$INSTALL_DIR/venv/bin/pip" install flask-wtf
    fi
    
    # Controleer andere cruciale modules
    for module in flask-login flask-sqlalchemy flask-migrate werkzeug gunicorn apscheduler; do
        if ! "$INSTALL_DIR/venv/bin/pip" show $module &>/dev/null; then
            echo -e "${YELLOW}$module is niet geïnstalleerd. Installeren...${NC}"
            "$INSTALL_DIR/venv/bin/pip" install $module
        fi
    done
    
    echo -e "${GREEN}✓ Python modules gecontroleerd en geïnstalleerd${NC}"
else
    echo -e "${RED}Virtual environment niet gevonden! Dit is onverwacht.${NC}"
    echo "Probeer handmatig een virtual environment te maken..."
    
    python3 -m venv venv
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip
    "$INSTALL_DIR/venv/bin/pip" install flask flask-login flask-sqlalchemy flask-wtf flask-migrate werkzeug gunicorn python-dotenv sqlalchemy apscheduler psycopg2-binary
    
    echo -e "${GREEN}✓ Nieuwe virtual environment aangemaakt en modules geïnstalleerd${NC}"
fi

# Stap 10: Controleer service configuratie
echo -e "\n${BLUE}[Stap 10]${NC} Controleren service configuratie"
if [ -f "/etc/systemd/system/radiologger.service" ]; then
    echo "Service configuratie gevonden, controleren op HOME directory en EnvironmentFile..."
    
    SERVICE_NEEDS_UPDATE=false
    
    # Controleer HOME directory setting
    if ! grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
        echo "HOME directory ontbreekt in service configuratie. Toevoegen..."
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
        SERVICE_NEEDS_UPDATE=true
    fi
    
    # Controleer EnvironmentFile setting
    if ! grep -q "EnvironmentFile=" /etc/systemd/system/radiologger.service; then
        echo "EnvironmentFile ontbreekt in service configuratie. Toevoegen..."
        sed -i '/\[Service\]/a EnvironmentFile=/opt/radiologger/.env' /etc/systemd/system/radiologger.service
        SERVICE_NEEDS_UPDATE=true
    fi
    
    if [ "$SERVICE_NEEDS_UPDATE" = true ]; then
        echo "Service configuratie aangepast, daemon-reload uitvoeren..."
        systemctl daemon-reload
    fi
    
    echo -e "${GREEN}✓ Service configuratie gecontroleerd en aangepast${NC}"
else
    echo -e "${RED}Service configuratie niet gevonden! Dit is onverwacht.${NC}"
    echo "Maak handmatig een service configuratie..."
    
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
    echo -e "${GREEN}✓ Nieuwe service configuratie aangemaakt${NC}"
fi

# Stap 11: Opschonen en services starten
echo -e "\n${BLUE}[Stap 11]${NC} Opschonen en services starten"
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

systemctl restart radiologger
systemctl restart nginx

echo -e "\n${GREEN}=========================================================${NC}"
echo -e "${GREEN}          RADIOLOGGER INSTALLATIE VOLTOOID!              ${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo ""
echo "Alle noodzakelijke bestanden zijn gedownload en geïnstalleerd."
echo "De Radiologger service en Nginx zijn herstart."
echo ""
echo "Te controleren:"
echo "1. Bekijk de servicestatus: ${BLUE}systemctl status radiologger${NC}"
echo "2. Test de website: ${BLUE}curl http://localhost${NC}"
echo ""
echo "Bij problemen:"
echo "- Controleer logs: ${BLUE}journalctl -u radiologger -n 50${NC}"
echo "- Voer diagnose uit: ${BLUE}$INSTALL_DIR/diagnose_502.sh${NC}"
echo ""
echo "Bedankt voor het gebruik van het volledige installatiescript!"