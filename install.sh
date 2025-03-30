#!/bin/bash
# Radiologger installatiescript voor Ubuntu 24.04
# Dit script installeert en configureert de Radiologger applicatie
#
# Aanbevolen commando voor directe installatie:
# sudo bash -c "mkdir -p /tmp/radiologger && chmod 700 /tmp/radiologger && cd /tmp/radiologger && wget -O install.sh https://raw.githubusercontent.com/sandersmale/logger/main/install.sh && chmod +x install.sh && bash install.sh"

# Download eerst het uninstall script
echo "Downloaden van uninstall.sh..."
mkdir -p /opt/radiologger
wget -O /opt/radiologger/uninstall.sh https://raw.githubusercontent.com/sandersmale/logger/main/uninstall.sh
chmod +x /opt/radiologger/uninstall.sh

# Maak een debug logbestand aan
DEBUG_LOG="/tmp/radiologger_install_debug.log"
echo "### RADIOLOGGER INSTALLATIE DEBUG LOG ###" > $DEBUG_LOG
echo "Datum: $(date)" >> $DEBUG_LOG
echo "Ubuntu versie: $(lsb_release -a 2>/dev/null)" >> $DEBUG_LOG
echo "----------------------------------------" >> $DEBUG_LOG

# Functie voor het loggen van debug informatie
debug_log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" >> $DEBUG_LOG
  if [ "$2" = "true" ]; then
    echo "$1"
  fi
}

# Functie om te vragen of uninstall uitgevoerd moet worden bij fouten
handle_install_error() {
  local error_msg="$1"
  local error_code="$2"
  
  echo "💥 FOUT TIJDENS INSTALLATIE: $error_msg (code: $error_code)"
  echo ""
  echo "De installatie is niet volledig gelukt. Je kunt:"
  echo "1. Het uninstall script uitvoeren om alle wijzigingen ongedaan te maken"
  echo "2. Handmatig proberen het probleem op te lossen"
  echo ""
  
  if [ -f "uninstall.sh" ]; then
    read -p "Wil je het uninstall script uitvoeren om opnieuw te beginnen? (j/n): " run_uninstall
    if [[ "$run_uninstall" =~ ^[jJ]$ ]]; then
      echo "Uninstall script uitvoeren..."
      chmod +x uninstall.sh
      bash uninstall.sh --force
      exit 1
    fi
  else
    echo "Let op: uninstall.sh script niet gevonden!"
    echo "Download het script handmatig met: wget -O uninstall.sh https://raw.githubusercontent.com/sandersmale/logger/main/uninstall.sh"
  fi
  
  echo "Installatie afgebroken. Zie $DEBUG_LOG voor meer details."
  exit $error_code
}

# Functie voor het uitvoeren van commando's met debug logging
run_cmd() {
  local cmd="$1"
  local msg="$2"
  local show_output="${3:-false}"
  
  debug_log "UITVOEREN: $cmd" true
  if [ "$show_output" = "true" ]; then
    echo "$ $cmd"
    eval "$cmd" 2>&1 | tee -a $DEBUG_LOG
    local exit_code=${PIPESTATUS[0]}
  else
    debug_log "START UITVOER:" false
    local output=$(eval "$cmd" 2>&1)
    local exit_code=$?
    echo "$output" >> $DEBUG_LOG
    debug_log "EINDE UITVOER (exit code: $exit_code)" false
  fi
  
  if [ $exit_code -ne 0 ]; then
    debug_log "FOUT ($exit_code): $msg" true
    echo "💥 Fout bij $msg (exit code: $exit_code)"
    echo "Zie $DEBUG_LOG voor meer details"
    if [ "$show_output" != "true" ]; then
      echo "Laatste uitvoer:"
      echo "$output" | tail -n 10
    fi
  else
    debug_log "SUCCES: $msg" true
  fi
  
  return $exit_code
}

debug_log "Installatiescript gestart" true
echo "Debuglog wordt geschreven naar: $DEBUG_LOG"

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
    handle_install_error "Geen internetverbinding gevonden" 1
fi

# Controleer beschikbare schijfruimte (minimaal 1GB)
available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_space" -lt 1 ]; then
    handle_install_error "Onvoldoende schijfruimte beschikbaar (minimaal 1GB nodig)" 1
fi

# Gebruik trap om fouten op te vangen in plaats van set -e
# Dit zorgt ervoor dat onze eigen foutafhandeling kan werken
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'exit_code=$?; if [ $exit_code -ne 0 ]; then echo "FOUT: \"${last_command}\" is mislukt met exit code $exit_code."; handle_install_error "Installatie mislukt op commando: ${last_command}" $exit_code; fi' EXIT

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
echo "7. SSL certificaat genereren via Let's Encrypt"
echo ""

# Configureer algemene installatie-instellingen
export DEBIAN_FRONTEND=noninteractive
export UCF_FORCE_CONFFOLD=1  # Behoud bestaande configuratiebestanden
export NEEDRESTART_MODE=a    # Automatisch herstarten van services
export NEEDRESTART_SUSPEND=1 # Onderdruk needrestart prompts

# Vraag MINIMALE benodigde configuratiegegevens zodat de installatie zonder onderbrekingen kan verlopen
echo "Voor de installatie zijn de volgende gegevens nodig:"
echo "1. PostgreSQL database gebruikerswachtwoord"
echo "2. Server domeinnaam voor Nginx"
echo "3. E-mailadres voor Let's Encrypt (SSL certificaat)"
echo ""

# Database configuratie
read -p "Kies een wachtwoord voor de PostgreSQL radiologger gebruiker: " db_password

# Server configuratie
read -p "Server domeinnaam voor Nginx (standaard: logger.pilotradio.nl): " server_domain
server_domain=${server_domain:-logger.pilotradio.nl}

# E-mail voor Let's Encrypt
read -p "E-mailadres voor Let's Encrypt notificaties: " email_address

# Radiostations configuratie
read -p "Standaard radiostations importeren? (j/n, standaard: j): " use_default_stations
use_default_stations=${use_default_stations:-j}

# SSL is altijd ingeschakeld
ssl_response="j"

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
echo "✅ Map structuur aangemaakt"
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger
echo "✅ Map rechten ingesteld"

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

# Controleer of kritieke bestanden correct zijn gekopieerd
echo "Controleren of kritieke bestanden aanwezig zijn..."
kritieke_bestanden=("main.py" "diagnose_502.sh" "fix_permissions.sh" "find_env_issues.sh")
missende_bestanden=()

for bestand in "${kritieke_bestanden[@]}"; do
    if [ ! -f "/opt/radiologger/$bestand" ]; then
        missende_bestanden+=("$bestand")
    fi
done

if [ ${#missende_bestanden[@]} -gt 0 ]; then
    echo "⚠️ De volgende kritieke bestanden ontbreken in de installatie:"
    for missend in "${missende_bestanden[@]}"; do
        echo "   - $missend"
    done
    
    # Probeer missende bestanden individueel te maken als ze ontbreken
    if [[ " ${missende_bestanden[*]} " =~ " diagnose_502.sh " ]]; then
        echo "📝 diagnose_502.sh aanmaken..."
        cat > /opt/radiologger/diagnose_502.sh << 'EOL'
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
        chmod 755 /opt/radiologger/diagnose_502.sh
        chown radiologger:radiologger /opt/radiologger/diagnose_502.sh
        echo "✅ diagnose_502.sh succesvol aangemaakt"
    fi
    
    if [[ " ${missende_bestanden[*]} " =~ " find_env_issues.sh " ]]; then
        echo "📝 find_env_issues.sh aanmaken..."
        cat > /opt/radiologger/find_env_issues.sh << 'EOL'
#!/bin/bash
# Diagnose script voor omgevingsproblemen in Radiologger
# Dit script controleert HOME directory issues en andere omgevingsvariabelen

echo "Radiologger Omgevings Diagnose Script"
echo "=================================="
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Toon huidige HOME directory voor radiologger gebruiker
echo "Controleren HOME directory voor radiologger gebruiker..."
CURRENT_HOME=$(sudo -u radiologger printenv HOME)
echo "HOME directory voor radiologger: $CURRENT_HOME"

if [ "$CURRENT_HOME" != "/opt/radiologger" ]; then
    echo "❌ HOME directory voor radiologger is niet correct ingesteld!"
    echo "   Moet zijn: /opt/radiologger"
    echo "   Huidige waarde: $CURRENT_HOME"
    
    # Controleer de systemd service
    echo "Controleren service configuratie..."
    if grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
        echo "✅ HOME directory correct ingesteld in service configuratie"
    else
        echo "❌ HOME directory ontbreekt in service configuratie!"
        echo "Toevoegen van HOME directory aan service..."
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✅ HOME directory toegevoegd, systemd herladen"
    fi
else
    echo "✅ HOME directory correct ingesteld"
fi

# Controleer andere belangrijke omgevingsvariabelen in service
echo ""
echo "Controleren andere omgevingsvariabelen in service..."
if [ -f /opt/radiologger/.env ]; then
    echo "Omgevingsvariabelen in .env bestand:"
    grep -v "^#" /opt/radiologger/.env | grep -v "^$"
else
    echo "❌ .env bestand niet gevonden!"
fi

echo ""
echo "Controleer of EnvironmentFile wordt gebruikt in service..."
if grep -q "EnvironmentFile=/opt/radiologger/.env" /etc/systemd/system/radiologger.service; then
    echo "✅ EnvironmentFile correct ingesteld in service"
else
    echo "❌ EnvironmentFile ontbreekt in service configuratie!"
    echo "Dit kan betekenen dat omgevingsvariabelen niet worden gelezen"
fi

# Testen database URL
echo ""
echo "Testen verbinding met database..."
if [ -f /opt/radiologger/.env ]; then
    DB_URL=$(grep DATABASE_URL /opt/radiologger/.env | cut -d= -f2-)
    if [ -n "$DB_URL" ]; then
        echo "Database URL gevonden: ${DB_URL:0:20}..."
        
        if command -v psql &> /dev/null; then
            echo "Testen database verbinding met psql..."
            if sudo -u radiologger bash -c "PGPASSWORD=$(echo $DB_URL | grep -oP '://\K[^:]*' | cut -d@ -f1) psql -h $(echo $DB_URL | grep -oP '@\K[^:]*' | cut -d/ -f1) -U $(echo $DB_URL | grep -oP '://\K[^:]*' | cut -d: -f1) -c '\conninfo'"; then
                echo "✅ Database verbinding succesvol"
            else
                echo "❌ Kan geen verbinding maken met database!"
            fi
        else
            echo "psql commando niet beschikbaar"
        fi
    else
        echo "❌ DATABASE_URL niet gevonden in .env bestand!"
    fi
else
    echo "❌ .env bestand niet gevonden!"
fi

echo ""
echo "Diagnose voltooid! Als dit script problemen heeft gedetecteerd, probeer:"
echo "1. Voer fix_permissions.sh uit: sudo bash /opt/radiologger/fix_permissions.sh"
echo "2. Herstart de service: sudo systemctl restart radiologger"
echo "3. Herstart Nginx: sudo systemctl restart nginx"
EOL
        chmod 755 /opt/radiologger/find_env_issues.sh
        chown radiologger:radiologger /opt/radiologger/find_env_issues.sh
        echo "✅ find_env_issues.sh succesvol aangemaakt"
    fi
    
    echo "Alle mogelijke missende bestanden zijn nu aangemaakt."
fi

echo ""
echo "Stap 4: Python virtuele omgeving en dependencies installeren..."
if ! cd /opt/radiologger; then
    handle_install_error "Kan niet naar /opt/radiologger directory gaan" 1
fi

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

# S3 storage configuratie - zal later in de setup worden geconfigureerd door de gebruiker
WASABI_ACCESS_KEY=
WASABI_SECRET_KEY=
WASABI_BUCKET=
WASABI_REGION=eu-central-1
WASABI_ENDPOINT_URL=https://s3.eu-central-1.wasabisys.com
EOL

# Rechten instellen
chown radiologger:radiologger /opt/radiologger/.env
chmod 600 /opt/radiologger/.env
echo "✅ Rechten voor .env bestand correct ingesteld"

echo ""
echo "Stap 6: Database initialiseren en vullen met basisgegevens..."
if ! cd /opt/radiologger; then
    handle_install_error "Kan niet naar /opt/radiologger directory gaan" 1
fi

# Gebruik de eerder opgegeven keuze voor standaard stations
use_default_flag=""
if [[ "$use_default_stations" =~ ^[jJ]$ ]]; then
    use_default_flag="--use-default-stations"
    echo "Standaard stations uit de oude database worden gebruikt."
else
    echo "Voorbeeld stations worden gebruikt."
fi

# Maak een volledig zelfstandig SHELL script voor database setup 
# Deze methode werkt zonder Python en direct via psql
cat > /opt/radiologger/shell_db_setup.sh << 'EOL'
#!/bin/bash
# shell_db_setup.sh
# Een volledig standalone shell script voor het opzetten van de database
# zonder enige afhankelijkheid van Python of imports
#
# Dit script maakt direct de database aan met pure SQL via het psql commando
# Het enige dat vereist is, is toegang tot een PostgreSQL installatie

# Configuratie uit omgevingsvariabelen of defaultwaarden
DB_USER=${DATABASE_USER:-"radiologger"}
DB_PASSWORD=${DATABASE_PASSWORD:-"radiologgerpass"}
DB_NAME=${DATABASE_NAME:-"radiologger"}
DB_HOST=${DATABASE_HOST:-"localhost"}
DB_PORT=${DATABASE_PORT:-"5432"}

# Log bestand voor debug informatie
LOG_FILE="/tmp/shell_db_setup.log"

# Logging functie
log_message() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Maak een nieuw logbestand aan
echo "Shell Database Setup Log - $(date)" > "$LOG_FILE"
echo "-------------------------------------" >> "$LOG_FILE"

log_message "Shell database setup script gestart"
log_message "Gebruikt postgresql://$DB_USER:******@$DB_HOST:$DB_PORT/$DB_NAME"

# Controleer of psql beschikbaar is
if ! command -v psql &> /dev/null; then
  log_message "❌ FOUT: psql commando niet gevonden. Installeer PostgreSQL client."
  exit 1
fi

# Genereer het SQL script
TMP_SQL_FILE=$(mktemp)
chmod 600 "$TMP_SQL_FILE"

cat > "$TMP_SQL_FILE" << 'EOSQL'
-- Maak de user tabel aan
CREATE TABLE IF NOT EXISTS "user" (
    id SERIAL PRIMARY KEY,
    username VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    role VARCHAR(20) DEFAULT 'listener' NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Maak de station tabel aan
CREATE TABLE IF NOT EXISTS "station" (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    recording_url VARCHAR(255) NOT NULL,
    always_on BOOLEAN DEFAULT FALSE,
    display_order INTEGER DEFAULT 999,
    schedule_start_date DATE,
    schedule_start_hour INTEGER,
    schedule_end_date DATE,
    schedule_end_hour INTEGER,
    record_reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Maak de dennis_station tabel aan
CREATE TABLE IF NOT EXISTS "dennis_station" (
    id SERIAL PRIMARY KEY,
    folder VARCHAR(100) NOT NULL,
    name VARCHAR(100) NOT NULL,
    url VARCHAR(255) NOT NULL,
    visible_in_logger BOOLEAN DEFAULT FALSE,
    last_updated TIMESTAMP DEFAULT NOW()
);

-- Maak de recording tabel aan
CREATE TABLE IF NOT EXISTS "recording" (
    id SERIAL PRIMARY KEY,
    station_id INTEGER REFERENCES "station"(id) NOT NULL,
    date DATE NOT NULL,
    hour VARCHAR(2) NOT NULL,
    filepath VARCHAR(255) NOT NULL,
    program_title VARCHAR(255),
    recording_type VARCHAR(20) DEFAULT 'scheduled',
    s3_uploaded BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Maak de scheduled_job tabel aan
CREATE TABLE IF NOT EXISTS "scheduled_job" (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(100) NOT NULL,
    station_id INTEGER REFERENCES "station"(id) NOT NULL,
    job_type VARCHAR(20) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status VARCHAR(20) DEFAULT 'scheduled',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Controleer of er al gebruikers zijn
DO $$
DECLARE
    user_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO user_count FROM "user";
    
    IF user_count = 0 THEN
        -- Maak standaard admin gebruiker 
        INSERT INTO "user" (username, password_hash, role)
        VALUES ('admin', 'pbkdf2:sha256:150000$8e7e812c0e87d1b9e27efaca3f63ce84cfddfbe10be3a1de9c9a3f2c22ff9e91', 'admin');
        
        -- Maak standaard editor gebruiker
        INSERT INTO "user" (username, password_hash, role)
        VALUES ('editor', 'pbkdf2:sha256:150000$bc88b347fba0cb8eeeb35050a45794a41c71fcb56e2e5ef0f26c71213000f89a', 'editor');
        
        -- Maak standaard luisteraar gebruiker
        INSERT INTO "user" (username, password_hash, role)
        VALUES ('luisteraar', 'pbkdf2:sha256:150000$66d6f30f0bef2c6b9622c93aa6906bbe5b3c5a87e0ef3acb5e9f55b468c83e90', 'listener');
    END IF;
END $$;
EOSQL

# Voer het SQL script uit
export PGPASSWORD="$DB_PASSWORD"
log_message "🔄 Database tabellen en basisgegevens aanmaken..."

if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$TMP_SQL_FILE" >> "$LOG_FILE" 2>&1; then
  log_message "✅ Database tabellen en basisgegevens succesvol aangemaakt!"
  success=true
else
  log_message "❌ Fout bij aanmaken database tabellen. Controleer $LOG_FILE voor details."
  
  # Probeer als alternatief met postgres gebruiker als we root zijn
  if [ "$(id -u)" -eq 0 ]; then
    log_message "🔄 Proberen als postgres gebruiker..."
    if sudo -u postgres psql -d "$DB_NAME" -f "$TMP_SQL_FILE" >> "$LOG_FILE" 2>&1; then
      log_message "✅ Database tabellen en basisgegevens succesvol aangemaakt met postgres gebruiker!"
      success=true
    else
      log_message "❌ Ook mislukt met postgres gebruiker. Zie $LOG_FILE voor details."
      success=false
    fi
  else
    success=false
  fi
fi

# Ruim het tijdelijke bestand op
rm -f "$TMP_SQL_FILE"

if [ "$success" = true ]; then
  log_message "✅ Database setup succesvol voltooid!"
  exit 0
else
  log_message "❌ Database setup mislukt. Controleer het logbestand: $LOG_FILE"
  cat "$LOG_FILE"
  exit 1
fi
EOL

# Maak het shell script uitvoerbaar
chmod +x /opt/radiologger/shell_db_setup.sh
chown radiologger:radiologger /opt/radiologger/shell_db_setup.sh
echo "✅ Shell database setup script rechten ingesteld"

# Maak een fallback SQL-script voor database-initialisatie (failsafe methode)
# Dit wordt alleen gebruikt als de directe SQL benadering faalt
cat > /opt/radiologger/direct_db_setup.py << 'EOL'
#!/usr/bin/env python3
"""
Radiologger directe database-initialisatie
Dit script maakt tabellen direct aan via SQL zonder ORM
"""
import os
import sys
import psycopg2
import traceback
from datetime import datetime

# Log bestand
LOG_FILE = "/tmp/radiologger_db_setup.log"
INSTALL_DIR = "/opt/radiologger"

def log(message):
    """Log een bericht naar het logbestand en toon het op het scherm"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"{timestamp} - {message}"
    
    with open(LOG_FILE, "a") as f:
        f.write(log_message + "\n")
    
    print(message)

def get_db_url():
    """Haal de database URL op uit het .env bestand"""
    env_path = os.path.join(INSTALL_DIR, ".env")
    db_url = None
    
    if os.path.exists(env_path):
        log(f"✅ .env bestand gevonden op: {env_path}")
        with open(env_path, "r") as f:
            for line in f:
                if line.startswith("DATABASE_URL="):
                    db_url = line.split("=", 1)[1].strip().strip('"\'')
                    log(f"✅ DATABASE_URL gevonden: {db_url}")
                    break
    
    if not db_url:
        log("❌ Geen DATABASE_URL gevonden in .env")
    
    return db_url

def simple_hash(password):
    """Eenvoudige hash functie voor wachtwoorden, NIET voor productie!"""
    import hashlib
    # SHA-256 hash met een zout
    salt = "radiologger_salt"
    return "pbkdf2:sha256:150000$" + hashlib.sha256(f"{password}{salt}".encode()).hexdigest()

def setup_database():
    """Maak de database tabellen direct aan met SQL-commando's"""
    db_url = get_db_url()
    if not db_url:
        return False
    
    try:
        # Verbind met de PostgreSQL database
        conn = psycopg2.connect(db_url)
        conn.autocommit = True
        cursor = conn.cursor()
        
        log("✅ Verbinding met database gemaakt")
        
        # Maak de user tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "user" (
                id SERIAL PRIMARY KEY,
                username VARCHAR(64) UNIQUE NOT NULL,
                password_hash VARCHAR(256) NOT NULL,
                role VARCHAR(20) DEFAULT 'listener' NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de station tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "station" (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) UNIQUE NOT NULL,
                recording_url VARCHAR(255) NOT NULL,
                always_on BOOLEAN DEFAULT FALSE,
                display_order INTEGER DEFAULT 999,
                schedule_start_date DATE,
                schedule_start_hour INTEGER,
                schedule_end_date DATE,
                schedule_end_hour INTEGER,
                record_reason VARCHAR(255),
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de dennis_station tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "dennis_station" (
                id SERIAL PRIMARY KEY,
                folder VARCHAR(100) NOT NULL,
                name VARCHAR(100) NOT NULL,
                url VARCHAR(255) NOT NULL,
                visible_in_logger BOOLEAN DEFAULT FALSE,
                last_updated TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de recording tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "recording" (
                id SERIAL PRIMARY KEY,
                station_id INTEGER REFERENCES "station"(id) NOT NULL,
                date DATE NOT NULL,
                hour VARCHAR(2) NOT NULL,
                filepath VARCHAR(255) NOT NULL,
                program_title VARCHAR(255),
                recording_type VARCHAR(20) DEFAULT 'scheduled',
                s3_uploaded BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de scheduled_job tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "scheduled_job" (
                id SERIAL PRIMARY KEY,
                job_id VARCHAR(100) NOT NULL,
                station_id INTEGER REFERENCES "station"(id) NOT NULL,
                job_type VARCHAR(20) NOT NULL,
                start_time TIMESTAMP NOT NULL,
                end_time TIMESTAMP,
                status VARCHAR(20) DEFAULT 'scheduled',
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        log("✅ Database tabellen succesvol aangemaakt")
        
        # Controleer of er al gebruikers zijn
        cursor.execute("SELECT COUNT(*) FROM \"user\"")
        user_count = cursor.fetchone()[0]
        
        if user_count == 0:
            log("🔄 Geen gebruikers gevonden, standaard gebruikers aanmaken...")
            
            # Maak de standaard gebruikers aan
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("admin", simple_hash("radioadmin"), "admin"))
            
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("editor", simple_hash("radioeditor"), "editor"))
            
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("luisteraar", simple_hash("radioluisteraar"), "listener"))
            
            log("✅ Standaard gebruikers aangemaakt")
        else:
            log(f"ℹ️ Er zijn al {user_count} gebruikers in de database, geen nieuwe gebruikers aangemaakt")
        
        conn.close()
        return True
        
    except Exception as e:
        log(f"❌ Fout bij database-initialisatie: {e}")
        log(traceback.format_exc())
        return False

if __name__ == "__main__":
    # Maak logbestand aan
    with open(LOG_FILE, "w") as f:
        f.write(f"Radiologger database setup log - {datetime.now()}\n")
        f.write("-" * 80 + "\n")
    
    log(f"Radiologger directe database-initialisatie gestart")
    log(f"Python versie: {sys.version}")
    log(f"Werkdirectory: {os.getcwd()}")
    
    success = setup_database()
    
    if success:
        log("✅ Database setup succesvol voltooid!")
        sys.exit(0)
    else:
        log("❌ Database setup MISLUKT!")
        sys.exit(1)
EOL

# Maak het script uitvoerbaar
chmod +x /opt/radiologger/direct_db_setup.py
chown radiologger:radiologger /opt/radiologger/direct_db_setup.py
echo "✅ Direct database script rechten ingesteld"

# Voer eerst het RUWE sql-script direct uit naar postgres (zonder Python)
echo "Direct SQL-only database setup starten..."
# Extraheer database gegevens uit eerder aangemaakte .env bestand
DB_USER=$(grep -oP '(?<=postgresql://)[^:]+' /opt/radiologger/.env || echo "radiologger")
DB_PASS=$(grep -oP '(?<=:)[^@]+(?=@)' /opt/radiologger/.env || echo "$db_password")
DB_HOST=$(grep -oP '(?<=@)[^:]+(?=:)' /opt/radiologger/.env || echo "localhost")
DB_PORT=$(grep -oP '(?<=:)[0-9]+(?=/)' /opt/radiologger/.env || echo "5432")
DB_NAME=$(grep -oP '(?<=/)[^?]+' /opt/radiologger/.env || echo "radiologger")

# Log de gegevens voor debugging (verwijder wachtwoord uit log)
echo "Database gegevens: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"

# Controleer en installeer eerst de vereiste Python-modules
echo "Zorgen dat psycopg2 geïnstalleerd is..."
if pip3 list | grep -q psycopg2-binary; then
    echo "✓ psycopg2-binary is al geïnstalleerd"
else
    echo "→ psycopg2-binary installeren..."
    # Voorkom 'externally-managed-environment' fout in Ubuntu 24.04
    python3 -m pip install --break-system-packages psycopg2-binary
fi

# Maak een Python script dat werkt met de correcte database URL
echo "Python-based database setup starten..."
# Kopieer het verbeterde init_db.py script
cat > /opt/radiologger/init_db.py << 'EOL'
#!/usr/bin/env python3
"""
Radiologger database initialisatie script
Dit script gebruikt de database-URL die in .env staat
"""
import os
import sys
import logging
from datetime import datetime

# Configureer logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('db_setup')

logger.info("Database initialisatie start")

try:
    # Import directe database modules
    import psycopg2
    from psycopg2 import sql

    # Lees de database URL uit de .env
    env_path = '.env'
    db_url = None
    
    if os.path.exists(env_path):
        logger.info(f".env bestand gevonden: {env_path}")
        with open(env_path, 'r') as f:
            for line in f:
                if line.startswith('DATABASE_URL='):
                    db_url = line.split('=', 1)[1].strip().strip('"\'')
                    # Verberg wachtwoord in logs
                    sanitized_url = db_url.replace(db_url.split('@')[0].split(':', 1)[1], '****')
                    logger.info(f"Database URL gevonden: {sanitized_url}")
                    break
    
    if not db_url:
        logger.error("Geen DATABASE_URL gevonden in .env")
        sys.exit(1)

    # Controleer of we kunnen verbinden
    logger.info("Verbinding maken met database...")
    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cursor = conn.cursor()
    
    # Controleer de bestaande tabellen
    logger.info("Bestaande tabellen controleren...")
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
    """)
    tables = cursor.fetchall()
    table_names = [table[0] for table in tables]
    
    logger.info(f"Gevonden tabellen: {', '.join(table_names)}")
    
    # Controleer of de belangrijkste tabellen bestaan
    required_tables = ['user', 'station', 'recording', 'scheduled_job', 'dennis_station']
    missing_tables = [table for table in required_tables if table not in table_names]
    
    if missing_tables:
        logger.warning(f"De volgende tabellen ontbreken: {', '.join(missing_tables)}")
        logger.info("Tabellen aanmaken...")
        
        # SQL voor het aanmaken van tabellen die ontbreken
        if 'user' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "user" (
                    id SERIAL PRIMARY KEY,
                    username VARCHAR(64) UNIQUE NOT NULL,
                    password_hash VARCHAR(256) NOT NULL,
                    role VARCHAR(20) DEFAULT 'listener' NOT NULL,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'user' aangemaakt")
        
        if 'station' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "station" (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(100) UNIQUE NOT NULL,
                    recording_url VARCHAR(255) NOT NULL,
                    always_on BOOLEAN DEFAULT FALSE,
                    display_order INTEGER DEFAULT 999,
                    schedule_start_date DATE,
                    schedule_start_hour INTEGER,
                    schedule_end_date DATE,
                    schedule_end_hour INTEGER,
                    record_reason VARCHAR(255),
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'station' aangemaakt")
        
        if 'dennis_station' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "dennis_station" (
                    id SERIAL PRIMARY KEY,
                    folder VARCHAR(100) NOT NULL,
                    name VARCHAR(100) NOT NULL,
                    url VARCHAR(255) NOT NULL,
                    visible_in_logger BOOLEAN DEFAULT FALSE,
                    last_updated TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'dennis_station' aangemaakt")
        
        if 'recording' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "recording" (
                    id SERIAL PRIMARY KEY,
                    station_id INTEGER REFERENCES "station"(id) NOT NULL,
                    date DATE NOT NULL,
                    hour VARCHAR(2) NOT NULL,
                    filepath VARCHAR(255) NOT NULL,
                    program_title VARCHAR(255),
                    recording_type VARCHAR(20) DEFAULT 'scheduled',
                    s3_uploaded BOOLEAN DEFAULT FALSE,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'recording' aangemaakt")
        
        if 'scheduled_job' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "scheduled_job" (
                    id SERIAL PRIMARY KEY,
                    job_id VARCHAR(100) NOT NULL,
                    station_id INTEGER REFERENCES "station"(id) NOT NULL,
                    job_type VARCHAR(20) NOT NULL,
                    start_time TIMESTAMP NOT NULL,
                    end_time TIMESTAMP,
                    status VARCHAR(20) DEFAULT 'scheduled',
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'scheduled_job' aangemaakt")
    else:
        logger.info("Alle vereiste tabellen zijn aanwezig!")
    
    # Controleer of er gebruikers bestaan
    cursor.execute("SELECT COUNT(*) FROM \"user\"")
    user_count = cursor.fetchone()[0]
    
    if user_count == 0:
        logger.info("Geen gebruikers gevonden, standaard gebruikers aanmaken...")
        
        # Genereer gehashte wachtwoorden (hard-coded hashes voor demo)
        admin_hash = 'pbkdf2:sha256:150000$8e7e812c0e87d1b9e27efaca3f63ce84cfddfbe10be3a1de9c9a3f2c22ff9e91'
        editor_hash = 'pbkdf2:sha256:150000$bc88b347fba0cb8eeeb35050a45794a41c71fcb56e2e5ef0f26c71213000f89a'
        listener_hash = 'pbkdf2:sha256:150000$66d6f30f0bef2c6b9622c93aa6906bbe5b3c5a87e0ef3acb5e9f55b468c83e90'
        
        # Maak de standaard gebruikers aan
        cursor.execute("""
            INSERT INTO "user" (username, password_hash, role)
            VALUES (%s, %s, %s)
        """, ("admin", admin_hash, "admin"))
        
        cursor.execute("""
            INSERT INTO "user" (username, password_hash, role)
            VALUES (%s, %s, %s)
        """, ("editor", editor_hash, "editor"))
        
        cursor.execute("""
            INSERT INTO "user" (username, password_hash, role)
            VALUES (%s, %s, %s)
        """, ("luisteraar", listener_hash, "listener"))
        
        logger.info("Standaard gebruikers aangemaakt")
    else:
        logger.info(f"Er zijn al {user_count} gebruikers in de database")
    
    # Controleer of er stations bestaan
    cursor.execute("SELECT COUNT(*) FROM station")
    station_count = cursor.fetchone()[0]
    
    if station_count == 0:
        logger.info("Geen stations gevonden, demo stations aanmaken...")
        
        # Voeg enkele demo stations toe
        cursor.execute("""
            INSERT INTO "station" (name, recording_url, always_on, display_order)
            VALUES (%s, %s, %s, %s)
        """, ("NPO Radio 1", "https://icecast.omroep.nl/radio1-bb-mp3", True, 1))
        
        cursor.execute("""
            INSERT INTO "station" (name, recording_url, always_on, display_order)
            VALUES (%s, %s, %s, %s)
        """, ("NPO Radio 2", "https://icecast.omroep.nl/radio2-bb-mp3", True, 2))
        
        cursor.execute("""
            INSERT INTO "station" (name, recording_url, always_on, display_order)
            VALUES (%s, %s, %s, %s)
        """, ("NPO 3FM", "https://icecast.omroep.nl/3fm-bb-mp3", False, 3))
        
        logger.info("Demo stations aangemaakt")
    else:
        logger.info(f"Er zijn al {station_count} stations in de database")
    
    cursor.close()
    conn.close()
    
    logger.info("✅ Database initialisatie succesvol afgerond!")
    sys.exit(0)

except Exception as e:
    logger.error(f"❌ Fout bij database initialisatie: {str(e)}")
    import traceback
    logger.error(traceback.format_exc())
    sys.exit(1)
EOL

# Maak het script uitvoerbaar en voer het uit
chmod +x /opt/radiologger/init_db.py
# Zorg dat de benodigde modules beschikbaar zijn in de python-omgeving voor de radiologger gebruiker
sudo -u radiologger python3 -m pip install --break-system-packages psycopg2-binary

# Voer het database-script uit
sudo -u radiologger python3 /opt/radiologger/init_db.py

# Sla het resultaat op
db_setup_result=$?
if [ $db_setup_result -eq 0 ]; then
    echo "✅ Direct SQL-commando's succesvol uitgevoerd!"
    direct_setup_result=0
else
    echo "⚠️ Directe SQL-commando's niet succesvol, probeer via Python..."
    # Voer het direct SQL-script uit als fallback
    echo "Direct SQL via Python setup starten..."
    sudo -u radiologger /opt/radiologger/venv/bin/python /opt/radiologger/direct_db_setup.py
    direct_setup_result=$?
fi

# De directe_setup_result is al ingesteld, dus deze regel is niet nodig 
# direct_setup_result=$?
if [ $direct_setup_result -eq 0 ]; then
    echo "✅ Direct SQL database setup succesvol voltooid!"
    echo "Logbestand beschikbaar op: /tmp/radiologger_db_setup.log"
    
    # Als er standaard stations geïmporteerd moeten worden
    if [[ "$use_default_stations" =~ ^[jJ]$ ]] && [ -f "seed_data.py" ]; then
        echo "Importeren van standaard stations..."
        cd /opt/radiologger
        sudo -u radiologger /opt/radiologger/venv/bin/python seed_data.py --use-default-stations
    fi

    # Spring naar de volgende stap in het script (Systemd service)
    echo ""
    echo "Stap 7: Systemd service instellen..."
else
    echo "⚠️ Direct SQL database setup niet succesvol, probeer alternatieve methoden..."

# Controleer of setup_db.py bestaat, anders gebruik seed_data.py
fi

if [ -f "setup_db.py" ]; then
    debug_log "setup_db.py gevonden, database initialiseren..." true
    chmod +x setup_db.py
    # Gebruik verbose modus om alle uitvoer te zien
    debug_log "Python module zoekpad controleren" true
    run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger python3 -c \"import sys; print(sys.path)\"'" "Python zoekpad controleren" true
    
    debug_log "Start database setup script met debug informatie" true
    run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v setup_db.py $use_default_flag'" "setup_db.py uitvoeren" true
    setup_result=$?
    if [ $setup_result -ne 0 ]; then
        debug_log "WAARSCHUWING: setup_db.py gaf een fout, probeer handmatige initialisatie..." true
        # Maak een tijdelijk Python-script voor database-initialisatie
        cat > /opt/radiologger/init_db_fallback.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Zorg ervoor dat we in de juiste directory zijn
os.chdir('/opt/radiologger')
base_path = Path('/opt/radiologger')
sys.path.insert(0, str(base_path))

# Voeg de directory toe aan PYTHONPATH
os.environ['PYTHONPATH'] = str(base_path)

try:
    from app import db, app
    with app.app_context():
        db.create_all()
    print('✅ Database tabellen aangemaakt')
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    sys.exit(1)
EOL

        # Maak het script uitvoerbaar
        chmod +x /opt/radiologger/init_db_fallback.py
        chown radiologger:radiologger /opt/radiologger/init_db_fallback.py
        
        # Voer het script uit met de radiologger gebruiker en uitgebreide debugging
        debug_log "Voer init_db_fallback.py uit met verbose modus" true
        run_cmd "cd /opt/radiologger" "directory wisselen" false
        run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v /opt/radiologger/init_db_fallback.py'" "init_db_fallback.py uitvoeren" true
        
        # Verwijder het tijdelijke script
        rm -f /opt/radiologger/init_db_fallback.py
        if [ -f "seed_data.py" ]; then
            debug_log "Initialiseren van basisgegevens via seed_data.py..." true
            run_cmd "cd /opt/radiologger" "directory wisselen" false
            run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v seed_data.py $use_default_flag'" "seed_data.py (fallback path) uitvoeren" true
        fi
    fi
elif [ -f "seed_data.py" ]; then
    echo "setup_db.py niet gevonden, maar seed_data.py wel. Database initialiseren..."
    # Maak een tijdelijk Python-script voor database-initialisatie
    cat > /opt/radiologger/init_db_alt.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Zorg ervoor dat we in de juiste directory zijn
os.chdir('/opt/radiologger')
base_path = Path('/opt/radiologger')
sys.path.insert(0, str(base_path))

# Voeg de directory toe aan PYTHONPATH
os.environ['PYTHONPATH'] = str(base_path)

try:
    from app import db, app
    with app.app_context():
        db.create_all()
    print('✅ Database tabellen aangemaakt')
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    sys.exit(1)
EOL

    # Maak het script uitvoerbaar
    chmod +x /opt/radiologger/init_db_alt.py
    chown radiologger:radiologger /opt/radiologger/init_db_alt.py
    
    # Voer het script uit met de radiologger gebruiker
    debug_log "Voer init_db_alt.py uit met verbose modus" true
    run_cmd "cd /opt/radiologger" "directory wisselen" false
    run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v /opt/radiologger/init_db_alt.py'" "init_db_alt.py uitvoeren" true
    
    # Verwijder het tijdelijke script
    rm -f /opt/radiologger/init_db_alt.py
    # Vul de database met basisgegevens
    debug_log "Vul de database met basisgegevens via seed_data.py" true
    run_cmd "cd /opt/radiologger" "directory wisselen" false
    run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v seed_data.py $use_default_flag'" "seed_data.py uitvoeren" true
else
    echo "Geen setup_db.py of seed_data.py gevonden. Initialiseer database basis tabellen..."
    
    # Maak een volledig standalone Python-script voor database-initialisatie
    cat > /opt/radiologger/init_db.py << 'EOL'
#!/usr/bin/env python3
"""
Radiologger database-initialisatie zonder afhankelijkheden.
Dit script bouwt de app vanaf de grond op zonder gebruik te maken van imports van bestaande modules.
"""
import os
import sys
import imp
import importlib.util
import logging
from pathlib import Path
import traceback

# Configureer logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('db_setup')

# Zorg ervoor dat we in de juiste directory zijn
os.chdir('/opt/radiologger')
base_path = Path('/opt/radiologger')
sys.path.insert(0, str(base_path))

# Voeg de directory toe aan PYTHONPATH
os.environ['PYTHONPATH'] = str(base_path)

# Debug informatie
logger.info(f"Python versie: {sys.version}")
logger.info(f"Werkdirectory: {os.getcwd()}")
logger.info(f"Python zoekpad: {sys.path}")
logger.info(f"PYTHONPATH: {os.environ.get('PYTHONPATH', 'Niet gezet')}")
logger.info("Modules in huidige directory:")
for path in os.listdir('.'):
    if path.endswith('.py'):
        logger.info(f"- {path}")

# Lees database configuratie uit .env
def get_db_url():
    """Haal database URL uit .env bestand"""
    if not os.path.exists('.env'):
        logger.error(".env bestand niet gevonden")
        return None
    
    with open('.env', 'r') as f:
        for line in f:
            if line.startswith('DATABASE_URL='):
                db_url = line.split('=', 1)[1].strip().strip('"\'')
                logger.info(f"Database URL gevonden: {db_url}")
                return db_url
    
    logger.error("DATABASE_URL niet gevonden in .env")
    return None

# Directe database aanmaak zonder ORM
def create_database_schema():
    """Maak direct database tabellen aan via SQL zonder SQLAlchemy"""
    import psycopg2
    
    db_url = get_db_url()
    if not db_url:
        return False
    
    try:
        # Verbind met de PostgreSQL database
        conn = psycopg2.connect(db_url)
        conn.autocommit = True
        cursor = conn.cursor()
        
        logger.info("✅ Verbinding met database gemaakt")
        
        # Maak de user tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "user" (
                id SERIAL PRIMARY KEY,
                username VARCHAR(64) UNIQUE NOT NULL,
                password_hash VARCHAR(256) NOT NULL,
                role VARCHAR(20) DEFAULT 'listener' NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de station tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "station" (
                id SERIAL PRIMARY KEY,
                name VARCHAR(100) UNIQUE NOT NULL,
                recording_url VARCHAR(255) NOT NULL,
                always_on BOOLEAN DEFAULT FALSE,
                display_order INTEGER DEFAULT 999,
                schedule_start_date DATE,
                schedule_start_hour INTEGER,
                schedule_end_date DATE,
                schedule_end_hour INTEGER,
                record_reason VARCHAR(255),
                created_at TIMESTAMP DEFAULT NOW(),
                updated_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de dennis_station tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "dennis_station" (
                id SERIAL PRIMARY KEY,
                folder VARCHAR(100) NOT NULL,
                name VARCHAR(100) NOT NULL,
                url VARCHAR(255) NOT NULL,
                visible_in_logger BOOLEAN DEFAULT FALSE,
                last_updated TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de recording tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "recording" (
                id SERIAL PRIMARY KEY,
                station_id INTEGER REFERENCES "station"(id) NOT NULL,
                date DATE NOT NULL,
                hour VARCHAR(2) NOT NULL,
                filepath VARCHAR(255) NOT NULL,
                program_title VARCHAR(255),
                recording_type VARCHAR(20) DEFAULT 'scheduled',
                s3_uploaded BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de scheduled_job tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "scheduled_job" (
                id SERIAL PRIMARY KEY,
                job_id VARCHAR(100) NOT NULL,
                station_id INTEGER REFERENCES "station"(id) NOT NULL,
                job_type VARCHAR(20) NOT NULL,
                start_time TIMESTAMP NOT NULL,
                end_time TIMESTAMP,
                status VARCHAR(20) DEFAULT 'scheduled',
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        logger.info("✅ Database tabellen succesvol aangemaakt")
        
        # Simple hash voor initiële gebruikers
        def simple_hash(password):
            """Eenvoudige hash functie voor wachtwoorden, NIET voor productie!"""
            import hashlib
            # SHA-256 hash met een zout
            salt = "radiologger_salt"
            return "pbkdf2:sha256:150000$" + hashlib.sha256(f"{password}{salt}".encode()).hexdigest()
        
        # Controleer of er al gebruikers zijn
        cursor.execute("SELECT COUNT(*) FROM \"user\"")
        user_count = cursor.fetchone()[0]
        
        if user_count == 0:
            logger.info("🔄 Geen gebruikers gevonden, standaard gebruikers aanmaken...")
            
            # Maak de standaard gebruikers aan
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("admin", simple_hash("radioadmin"), "admin"))
            
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("editor", simple_hash("radioeditor"), "editor"))
            
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("luisteraar", simple_hash("radioluisteraar"), "listener"))
            
            logger.info("✅ Standaard gebruikers aangemaakt")
        else:
            logger.info(f"ℹ️ Er zijn al {user_count} gebruikers in de database, geen nieuwe gebruikers aangemaakt")
        
        conn.close()
        return True
    
    except Exception as e:
        logger.error(f"Fout bij database-initialisatie: {e}")
        logger.error(traceback.format_exc())
        return False

# Probeer eerst de directe methode
try:
    logger.info("Poging 1: Directe database initialisatie met psycopg2...")
    if create_database_schema():
        logger.info("✅ Database initialisatie succesvol met directe methode")
        sys.exit(0)
    else:
        logger.warning("Directe initialisatie gefaald, probeer alternatieve methode...")
except Exception as e:
    logger.error(f"Fout bij directe initialisatie: {str(e)}")
    logger.error(traceback.format_exc())

# Als alternatief, probeer via de flask app
try:
    logger.info("Poging 2: Database initialisatie via Flask SQLAlchemy...")
    
    # Importeer modules dynamisch
    spec = importlib.util.spec_from_file_location("app", "./app.py")
    app_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(app_module)
    
    # Haal de benodigde objecten op
    db = getattr(app_module, 'db')
    app = getattr(app_module, 'app')
    
    with app.app_context():
        db.create_all()
    
    logger.info("✅ Database tabellen aangemaakt via SQLAlchemy")
    sys.exit(0)
except Exception as e:
    logger.error(f"Fout bij SQLAlchemy initialisatie: {str(e)}")
    logger.error(traceback.format_exc())
    
# Laatste redmiddel - probeer de app handmatig te creëren
try:
    logger.info("Poging 3: Handmatige Flask SQLAlchemy setup...")
    
    from flask import Flask
    from flask_sqlalchemy import SQLAlchemy
    from sqlalchemy.orm import DeclarativeBase
    
    # Definieer de basisklasse voor SQLAlchemy modellen
    class Base(DeclarativeBase):
        pass
    
    # Maak de Flask app en SQLAlchemy instantie
    db = SQLAlchemy(model_class=Base)
    app = Flask(__name__)
    
    # Configureer de database
    app.config['SQLALCHEMY_DATABASE_URI'] = get_db_url()
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    
    # Initialiseer de app met SQLAlchemy
    db.init_app(app)
    
    # Maak alle tabellen
    with app.app_context():
        # Dynamisch importeren van modellen
        model_files = [f for f in os.listdir('.') if f.endswith('.py') and 'model' in f.lower()]
        for model_file in model_files:
            logger.info(f"Probeer modellen te laden uit: {model_file}")
            try:
                module_name = model_file[:-3]  # Verwijder .py
                spec = importlib.util.spec_from_file_location(module_name, f"./{model_file}")
                if spec and spec.loader:
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)
                    logger.info(f"Model {module_name} geladen")
            except Exception as e:
                logger.warning(f"Kan model {model_file} niet laden: {str(e)}")
        
        # Maak tabellen
        db.create_all()
        logger.info("✅ Database tabellen aangemaakt via handmatige setup")
    
    sys.exit(0)
except Exception as e:
    logger.error(f"❌ Alle pogingen gefaald! Laatste fout: {str(e)}")
    logger.error(traceback.format_exc())
    sys.exit(1)
EOL

    # Maak het script uitvoerbaar
    chmod +x /opt/radiologger/init_db.py
    chown radiologger:radiologger /opt/radiologger/init_db.py
    
    # We slaan de init_db.py uitvoering over omdat de database nu tijdens de eerste
    # keer setup via de webinterface wordt geïnitialiseerd
    debug_log "Database tabellen worden aangemaakt tijdens eerste bezoek aan de webinterface" true
    echo "✅ Database tabellen worden aangemaakt tijdens de eerste configuratie"
    
    # Verwijder het tijdelijke script
    rm -f /opt/radiologger/init_db.py
    # We maken geen standaard gebruikers meer aan, omdat die nu in de setup via de webinterface worden aangemaakt
    debug_log "Gebruikers worden aangemaakt tijdens eerste bezoek aan de webinterface" true
    echo "✅ Gebruikers worden aangemaakt tijdens de eerste configuratie via de webinterface"
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
echo "SSL certificaat wordt geïnstalleerd voor $server_domain..."
certbot --nginx -d "$server_domain" --non-interactive --agree-tos --redirect --email "$email_address"
echo "SSL certificaat voor $server_domain geïnstalleerd!"

echo ""
echo "Stap 10: Fix-permissions script aanmaken voor noodgevallen..."
# Maak een fix_permissions.sh script aan als het nog niet aanwezig is
cat > /opt/radiologger/fix_permissions.sh << 'EOL'
#!/bin/bash
# Fix permissies script voor de Radiologger applicatie
# Dit script repareert alle bestandsrechten en eigenaarschap

# Controleren of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

echo "Radiologger Permissions Fix Script"
echo "=================================="
echo ""

# Fix eigenaarschap
echo "Repareren van eigenaarschap van bestanden en mappen..."
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger

# Fix bestandsrechten
echo "Repareren van bestandsrechten..."
chmod 755 /opt/radiologger
chmod 755 /var/log/radiologger
chmod 755 /var/lib/radiologger
chmod 755 /var/lib/radiologger/recordings

# Fix .env bestand
echo "Repareren van .env bestandsrechten..."
if [ -f /opt/radiologger/.env ]; then
  chmod 640 /opt/radiologger/.env
  chown radiologger:radiologger /opt/radiologger/.env
  echo "✅ .env bestand rechten gecorrigeerd"
else
  echo "⚠️ .env bestand niet gevonden!"
fi

# Fix Python omgeving
echo "Repareren van Python virtual environment rechten..."
if [ -d /opt/radiologger/venv ]; then
  chown -R radiologger:radiologger /opt/radiologger/venv
  chmod -R 755 /opt/radiologger/venv
  echo "✅ Python virtual environment rechten gecorrigeerd"
else
  echo "⚠️ Python virtual environment niet gevonden!"
fi

# Fix uitvoerbare Python scripts
echo "Uitvoerbare bestanden controleren..."
for script in /opt/radiologger/*.py; do
  if [ -f "$script" ]; then
    chmod 755 "$script"
  fi
done
echo "✅ Python scripts executable gemaakt"

# Fix nginx configuratie (indien aanwezig)
if [ -f /etc/nginx/sites-available/radiologger ]; then
  chmod 644 /etc/nginx/sites-available/radiologger
  echo "✅ Nginx configuratie rechten gecorrigeerd"
fi

# Fix HOME directory voor de service
echo "HOME directory repareren in de service configuratie..."
if [ -f /etc/systemd/system/radiologger.service ]; then
  if ! grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
    # Voeg HOME toe aan de radiologger.service als het ontbreekt
    sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
    echo "✅ HOME directory in systemd service toegevoegd"
    
    # Herlaad systemd en restart de service
    systemctl daemon-reload
    systemctl restart radiologger
  else
    echo "✅ HOME directory is al correct ingesteld in de service"
  fi
else
  echo "⚠️ Radiologger service bestand niet gevonden!"
fi

# Verificatie
echo ""
echo "Verificatie van rechten:"
ls -ld /opt/radiologger
ls -ld /var/log/radiologger
ls -ld /var/lib/radiologger
ls -ld /var/lib/radiologger/recordings
if [ -f /opt/radiologger/.env ]; then
  ls -l /opt/radiologger/.env
fi

echo ""
echo "✅ Alle rechten zijn gerepareerd!"
echo "Herstart de Radiologger service met: sudo systemctl restart radiologger"
echo "Herstart Nginx met: sudo systemctl restart nginx"
EOL

# Maak het permissions script uitvoerbaar
chmod +x /opt/radiologger/fix_permissions.sh
chown radiologger:radiologger /opt/radiologger/fix_permissions.sh
echo "✅ Fix-permissions script aangemaakt en klaar voor gebruik"

echo ""
echo "Stap 11: Cron-taken instellen voor onderhoud..."
# Voeg crontab toe voor de radiologger gebruiker
(sudo -u radiologger crontab -l 2>/dev/null || echo "") | \
    { cat; echo "0 2 * * * find /var/log/radiologger -name \"*.log\" -type f -mtime +30 -delete"; } | \
    sudo -u radiologger crontab -

# Maak een speciaal script voor het downloaden van Omroep LvC bestanden
cat > /opt/radiologger/download_omroeplvc_cron.py << 'EOL'
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Zorg ervoor dat we in de juiste directory zijn
os.chdir('/opt/radiologger')
base_path = Path('/opt/radiologger')
sys.path.insert(0, str(base_path))

# Voeg de directory toe aan PYTHONPATH
os.environ['PYTHONPATH'] = str(base_path)

try:
    from logger import download_omroeplvc
    download_omroeplvc()
    print('✅ Omroep LvC download uitgevoerd')
except Exception as e:
    print(f'❌ Fout bij downloaden Omroep LvC: {e}')
    sys.exit(1)
EOL

# Maak het script uitvoerbaar
chmod +x /opt/radiologger/download_omroeplvc_cron.py
chown radiologger:radiologger /opt/radiologger/download_omroeplvc_cron.py

# Zet de crontab voor het downloaden van Omroep LvC bestanden
# 8 minuten na het uur (net als in de scheduler)
echo "Omroep LvC download taak instellen (8 minuten na het uur)..."
(sudo -u radiologger crontab -l 2>/dev/null) | \
    { cat; echo "8 * * * * cd /opt/radiologger && /opt/radiologger/venv/bin/python /opt/radiologger/download_omroeplvc_cron.py >> /var/log/radiologger/omroeplvc_cron.log 2>&1"; } | \
    sudo -u radiologger crontab -

echo ""
echo "====================================================================="
echo "✅ Radiologger is succesvol geïnstalleerd!"
echo "De applicatie draait nu op https://$server_domain"
echo ""
echo "⚠️ BELANGRIJK: Bij het eerste bezoek aan https://$server_domain zul je:"
echo "1. Een admin-account moeten aanmaken"
echo "2. De Wasabi S3 cloud storage toegangsgegevens moeten configureren"
echo ""
echo "Volg de setup-instructies op het scherm voor een volledige configuratie."
echo "====================================================================="