#!/bin/bash
# Radiologger installatiescript voor Ubuntu 24.04
# Dit script installeert en configureert de Radiologger applicatie
#
# Aanbevolen commando voor directe installatie:
# sudo bash -c "mkdir -p /tmp/radiologger && chmod 700 /tmp/radiologger && cd /tmp/radiologger && wget -O install.sh https://raw.githubusercontent.com/sandersmale/logger/main/install.sh && chmod +x install.sh && bash install.sh"

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
echo "✅ Rechten voor .env bestand correct ingesteld"

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

# Maak een éénvoudig losstaand SQL-script dat DIRECT naar psql gaat
# Deze methode gebruikt GEEN python imports, maar gaat rechtstreeks naar PostgreSQL
cat > /opt/radiologger/setup_db.sql << 'EOL'
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
EOL

# Maak een direct SQL-script voor database-initialisatie (failsafe methode)
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

# Voer het SQL-script direct uit als de postgres gebruiker (GEEN PYTHON NODIG)
echo "Directe SQL-commando's uitvoeren naar PostgreSQL..."
sudo -u postgres psql -d $DB_NAME -f /opt/radiologger/setup_db.sql

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
    
    # Voer het script uit met de radiologger gebruiker
    debug_log "Voer init_db.py uit met verbose modus" true
    run_cmd "cd /opt/radiologger" "directory wisselen" false
    run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v /opt/radiologger/init_db.py'" "init_db.py uitvoeren" true
    
    # Verwijder het tijdelijke script
    rm -f /opt/radiologger/init_db.py
    # Maak een tijdelijk Python-script voor het aanmaken van standaard gebruikers
    cat > /opt/radiologger/create_users.py << 'EOL'
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
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken gebruikers: {e}')
    sys.exit(1)
EOL

    # Maak het script uitvoerbaar
    chmod +x /opt/radiologger/create_users.py
    chown radiologger:radiologger /opt/radiologger/create_users.py
    
    # Voer het script uit met de radiologger gebruiker
    debug_log "Voer create_users.py uit met verbose modus" true
    run_cmd "cd /opt/radiologger" "directory wisselen" false
    run_cmd "sudo -u radiologger bash -c 'cd /opt/radiologger && PYTHONPATH=/opt/radiologger /opt/radiologger/venv/bin/python -v /opt/radiologger/create_users.py'" "create_users.py uitvoeren" true
    
    # Verwijder het tijdelijke script
    rm -f /opt/radiologger/create_users.py
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