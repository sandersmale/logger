#!/bin/bash

# diagnose_ubuntu24.sh
# Diagnostisch script voor Ubuntu 24.04 specifieke problemen met Radiologger
# Dit script detecteert en lost veelvoorkomende problemen op met pip en venv in Ubuntu 24.04

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/radiologger"
VENV_DIR="$INSTALL_DIR/venv"
LOG_FILE="/tmp/radiologger_ubuntu24_diagnose.log"

echo -e "${YELLOW}[INFO]${NC} Ubuntu 24.04 diagnose voor Radiologger gestart"
echo -e "${YELLOW}[INFO]${NC} Logbestand: $LOG_FILE"
echo "" > "$LOG_FILE"

# Controleer of we Ubuntu 24.04 gebruiken
echo -e "${YELLOW}[CHECK]${NC} Controleren of we op Ubuntu 24.04 draaien..."
if grep -q "Ubuntu 24" /etc/os-release 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Ubuntu 24.04 gedetecteerd" | tee -a "$LOG_FILE"
    UBUNTU24=true
else
    echo -e "${YELLOW}[INFO]${NC} Geen Ubuntu 24.04 gedetecteerd, maar script gaat door met diagnose" | tee -a "$LOG_FILE"
    UBUNTU24=false
fi

# Controleer of Radiologger installatiemap bestaat
echo -e "${YELLOW}[CHECK]${NC} Controleren of Radiologger installatiemap bestaat..."
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${GREEN}[OK]${NC} Radiologger installatiemap bestaat: $INSTALL_DIR" | tee -a "$LOG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Radiologger installatiemap niet gevonden: $INSTALL_DIR" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}[INFO]${NC} Zorg ervoor dat Radiologger correct is geïnstalleerd" | tee -a "$LOG_FILE"
    exit 1
fi

# Controleer of Python virtual environment bestaat
echo -e "${YELLOW}[CHECK]${NC} Controleren of Python virtual environment bestaat..."
if [ -d "$VENV_DIR" ]; then
    echo -e "${GREEN}[OK]${NC} Python virtual environment gevonden: $VENV_DIR" | tee -a "$LOG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Python virtual environment niet gevonden: $VENV_DIR" | tee -a "$LOG_FILE"
    
    # Maak een nieuw venv aan als deze niet bestaat
    echo -e "${YELLOW}[FIX]${NC} Aanmaken nieuw Python virtual environment..." | tee -a "$LOG_FILE"
    cd "$INSTALL_DIR"
    python3 -m venv "$VENV_DIR" 2>> "$LOG_FILE"
    
    if [ -d "$VENV_DIR" ]; then
        echo -e "${GREEN}[OK]${NC} Nieuw Python virtual environment aangemaakt" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}[ERROR]${NC} Kon geen nieuw Python virtual environment aanmaken" | tee -a "$LOG_FILE"
        echo -e "${YELLOW}[INFO]${NC} Controleer of python3-venv is geïnstalleerd: sudo apt install python3-venv" | tee -a "$LOG_FILE"
        exit 1
    fi
fi

# Controleer of requirements.txt bestand bestaat
echo -e "${YELLOW}[CHECK]${NC} Controleren of requirements.txt bestand bestaat..."
if [ -f "$INSTALL_DIR/requirements.txt" ]; then
    echo -e "${GREEN}[OK]${NC} requirements.txt gevonden" | tee -a "$LOG_FILE"
else
    echo -e "${RED}[ERROR]${NC} requirements.txt niet gevonden" | tee -a "$LOG_FILE"
    
    # Maak requirements.txt aan als deze niet bestaat
    echo -e "${YELLOW}[FIX]${NC} Aanmaken van requirements.txt met essentiële dependencies..." | tee -a "$LOG_FILE"
    cat > "$INSTALL_DIR/requirements.txt" << EOF
Flask>=2.2.0
flask-sqlalchemy>=3.0.0
Flask-Migrate>=4.0.0
Flask-Login>=0.6.0
Flask-WTF>=1.1.0
APScheduler>=3.10.0
python-dotenv>=1.0.0
boto3>=1.28.0
psycopg2-binary>=2.9.0
gunicorn>=21.0.0
psutil>=5.9.0
requests>=2.30.0
trafilatura>=1.6.0
email-validator>=2.0.0
werkzeug>=2.3.0
wtforms>=3.0.0
Flask-SQLAlchemy>=3.0.0
SQLAlchemy>=2.0.0
EOF
    echo -e "${GREEN}[OK]${NC} requirements.txt aangemaakt" | tee -a "$LOG_FILE"
fi

# Installeer dependencies met --break-system-packages als we op Ubuntu 24.04 draaien
echo -e "${YELLOW}[CHECK]${NC} Installeren/herstellen van dependencies..."
cd "$INSTALL_DIR"
source "$VENV_DIR/bin/activate" 2>> "$LOG_FILE"

if $UBUNTU24; then
    echo -e "${YELLOW}[FIX]${NC} Installeren met --break-system-packages op Ubuntu 24.04..." | tee -a "$LOG_FILE"
    pip install --upgrade pip --break-system-packages 2>> "$LOG_FILE"
    pip install -r requirements.txt --break-system-packages 2>> "$LOG_FILE"
    pip install gunicorn psycopg2-binary --break-system-packages 2>> "$LOG_FILE"
else
    echo -e "${YELLOW}[FIX]${NC} Standaard installatie van packages..." | tee -a "$LOG_FILE"
    pip install --upgrade pip 2>> "$LOG_FILE"
    pip install -r requirements.txt 2>> "$LOG_FILE"
    pip install gunicorn psycopg2-binary 2>> "$LOG_FILE"
fi

# Controleer of essentiële packages zijn geïnstalleerd
echo -e "${YELLOW}[CHECK]${NC} Controleren of essentiële packages zijn geïnstalleerd..."
if pip list | grep -q "Flask" && pip list | grep -q "gunicorn"; then
    echo -e "${GREEN}[OK]${NC} Essentiële packages zijn geïnstalleerd" | tee -a "$LOG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Essentiële packages ontbreken nog steeds na installatie" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}[INFO]${NC} Handmatige installatie nodig. Probeer de volgende commando's:" | tee -a "$LOG_FILE"
    echo -e "cd $INSTALL_DIR" | tee -a "$LOG_FILE"
    echo -e "source venv/bin/activate" | tee -a "$LOG_FILE"
    echo -e "pip install Flask gunicorn flask-sqlalchemy --break-system-packages" | tee -a "$LOG_FILE"
fi

deactivate

# Controleer permissies
echo -e "${YELLOW}[CHECK]${NC} Controleren en herstellen van bestandspermissies..."
if [ -f "$INSTALL_DIR/fix_permissions.sh" ]; then
    echo -e "${YELLOW}[FIX]${NC} Uitvoeren van fix_permissions.sh script..." | tee -a "$LOG_FILE"
    bash "$INSTALL_DIR/fix_permissions.sh" >> "$LOG_FILE" 2>&1
    echo -e "${GREEN}[OK]${NC} Permissies hersteld" | tee -a "$LOG_FILE"
else
    echo -e "${YELLOW}[FIX]${NC} Handmatig herstellen van permissies..." | tee -a "$LOG_FILE"
    chown -R radiologger:radiologger "$INSTALL_DIR" 2>> "$LOG_FILE"
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \; 2>> "$LOG_FILE"
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \; 2>> "$LOG_FILE"
    find "$INSTALL_DIR" -name "*.sh" -exec chmod 755 {} \; 2>> "$LOG_FILE"
    find "$INSTALL_DIR" -name "*.py" -exec chmod 644 {} \; 2>> "$LOG_FILE"
    chmod 755 "$INSTALL_DIR/venv/bin/python" "$INSTALL_DIR/venv/bin/gunicorn" 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Permissies handmatig hersteld" | tee -a "$LOG_FILE"
fi

# Herstart de service
echo -e "${YELLOW}[CHECK]${NC} Herstarten van de Radiologger service..."
systemctl restart radiologger 2>> "$LOG_FILE"
sleep 3

if systemctl is-active --quiet radiologger; then
    echo -e "${GREEN}[OK]${NC} Radiologger service succesvol herstart" | tee -a "$LOG_FILE"
else
    echo -e "${RED}[ERROR]${NC} Radiologger service kon niet worden herstart" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}[INFO]${NC} Bekijk service logs: sudo journalctl -u radiologger --no-pager -n 50" | tee -a "$LOG_FILE"
fi

# Toon samenvatting
echo -e "\n${GREEN}=== Diagnose voltooid ===${NC}"
echo -e "${YELLOW}[INFO]${NC} Bekijk het logbestand voor meer details: $LOG_FILE"
echo -e "${YELLOW}[INFO]${NC} Als problemen blijven bestaan, controleer het volgende:"
echo -e "  - sudo systemctl status radiologger"
echo -e "  - sudo journalctl -u radiologger --no-pager -n 50"
echo -e "  - sudo cat /var/log/radiologger/error.log"
echo -e "  - sudo tail -f /var/log/apache2/error.log"

exit 0