#!/bin/bash

# Verbeterd Radiologger Installatiescript
# Dit script controleert eerst of alle benodigde bestanden en mappen aanwezig zijn
# en installeert dan de Radiologger applicatie

# Setup logbestand
LOG_FILE="/tmp/radiologger_install.log"
ERROR_LOG="/tmp/radiologger_install_error.log"

# Maak logbestanden aan/leeg
> "$LOG_FILE"
> "$ERROR_LOG"

# Versie en datum
INSTALL_VERSION="2.0.1"
INSTALL_DATE="2025-03-31"

# Logfuncties
log_error() {
    echo -e "\e[31m$(date '+%Y-%m-%d %H:%M:%S') - FOUT: $1\e[0m" | tee -a "$ERROR_LOG" >&2
}

log_warning() {
    echo -e "\e[33m$(date '+%Y-%m-%d %H:%M:%S') - WAARSCHUWING: $1\e[0m" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "\e[36m$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1\e[0m" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "\e[32m$(date '+%Y-%m-%d %H:%M:%S') - SUCCES: $1\e[0m" | tee -a "$LOG_FILE"
}

# Log system informatie voor debugging
log_system_info() {
    log_info "Radiologger Installatie v$INSTALL_VERSION ($INSTALL_DATE)"
    log_info "Systeem: $(uname -a)"
    if [ -f /etc/os-release ]; then
        log_info "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    fi
    log_info "Python versie: $(python3 --version 2>&1)"
    log_info "PostgreSQL versie: $(psql --version 2>&1 || echo 'Niet geïnstalleerd')"
    log_info "Apache versie: $(apache2 -v 2>&1 | grep version || echo 'Niet geïnstalleerd')"
}

# Functie om kritieke fouten af te handelen
handle_critical_error() {
    local error_message="$1"
    local error_code="${2:-1}"
    
    log_error "$error_message"
    log_error "Installatie afgebroken met code $error_code. Zie $ERROR_LOG voor details."
    
    # Toon laatste 10 regels van error log
    echo -e "\nLaatste details uit error log:"
    tail -n 10 "$ERROR_LOG"
    
    exit $error_code
}

# Controleer of het script als root draait
if [ "$EUID" -ne 0 ]; then
    log_error "Dit script moet als root worden uitgevoerd. Gebruik 'sudo bash $0'"
    exit 1
fi

# Banner tonen
echo -e "\e[1;36m====================================================================\e[0m"
echo -e "\e[1;36m          Radiologger - Betrouwbare Installatie v$INSTALL_VERSION \e[0m"
echo -e "\e[1;36m====================================================================\e[0m"

# Log systeeminformatie
log_system_info

# Stap 1: Controleer of we in de juiste directory zijn
CURRENT_DIR=$(pwd)
log_info "Huidige directory: $CURRENT_DIR"

# Stap 2: Controleer of essentiële bestanden aanwezig zijn
ESSENTIAL_FILES=(
    "main.py" "app.py" "forms.py" "auth.py" "emergency_forms.py" 
    "radiologger.service" "radiologger_apache.conf" "models.py" 
    "routes.py" "logger.py" "player.py" "schedule.py" "storage.py"
    "config.py" "station_manager.py" "init_db.py" "api_integrations.py"
)
MISSING_FILES=()

log_info "Controleren van essentiële bestanden..."

for file in "${ESSENTIAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        log_error "Essentieel bestand ontbreekt: $file"
        MISSING_FILES+=("$file")
    else
        log_info "Bestand gevonden: $file"
    fi
done

# Probeer missende bestanden te downloaden als ze nog niet bestaan
if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    log_info "Proberen ontbrekende bestanden te downloaden..."
    
    # Probeer eerst met directe download
    for file in "${MISSING_FILES[@]}"; do
        log_info "Downloaden van ontbrekend bestand: $file"
        wget -q "https://raw.githubusercontent.com/sandersmale/logger/main/$file" || {
            log_warning "Kan $file niet downloaden via directe methode, probeer alternatieve methode..."
            # Alternatieve download via GitHub API
            DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/sandersmale/logger/contents/$file" | grep -o '"download_url": "[^"]*"' | cut -d'"' -f4)
            if [ ! -z "$DOWNLOAD_URL" ]; then
                wget -q -O "$file" "$DOWNLOAD_URL" || {
                    log_error "Kan $file niet downloaden met beide methoden. Installatie kan niet doorgaan."
                    handle_critical_error "Kritiek bestand $file ontbreekt en kan niet worden gedownload" 5
                }
            else
                log_error "Kan download URL voor $file niet vinden"
                handle_critical_error "Kritiek bestand $file ontbreekt en kan niet worden gedownload" 5
            fi
        }
        log_success "Bestand $file succesvol gedownload"
    done
fi

# Controleer of cruciale bestanden nu aanwezig zijn
CRUCIAL_FILES=("main.py" "app.py" "models.py")
for file in "${CRUCIAL_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        handle_critical_error "Kritiek bestand $file ontbreekt nog steeds na download pogingen. Installatie kan niet doorgaan." 5
    fi
done

# Stap 3: Controleer of vereiste mappen aanwezig zijn
REQUIRED_DIRS=("templates" "static" "static/css" "static/js")
MISSING_DIRS=()

log_info "Controleren van vereiste mappen..."

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        log_error "Vereiste map ontbreekt: $dir"
        MISSING_DIRS+=("$dir")
    else
        log_info "Map gevonden: $dir"
    fi
done

# Probeer missende mappen aan te maken en bestanden te downloaden als nodig
if [ ${#MISSING_DIRS[@]} -gt 0 ]; then
    log_info "Aanmaken van ontbrekende mappen en downloaden van bestanden..."
    
    for dir in "${MISSING_DIRS[@]}"; do
        log_info "Aanmaken map: $dir"
        mkdir -p "$dir" || {
            log_error "Kan map $dir niet aanmaken. Installatie kan niet doorgaan."
            exit 1
        }
        
        # Download bestanden voor deze map
        case "$dir" in
            "templates")
                log_info "Downloaden templates bestanden..."
                curl -s https://api.github.com/repos/sandersmale/logger/contents/templates | grep -o "\"download_url\": \"[^\"]*\"" | cut -d"\"" -f4 | while read url; do
                    wget -q -P templates "$url" || log_error "Kan template bestand niet downloaden: $url"
                done
                ;;
            "static")
                log_info "Downloaden static bestanden..."
                curl -s https://api.github.com/repos/sandersmale/logger/contents/static | grep -o "\"download_url\": \"[^\"]*\"" | cut -d"\"" -f4 | while read url; do
                    wget -q -P static "$url" || log_error "Kan static bestand niet downloaden: $url"
                done
                ;;
            "static/css")
                log_info "Downloaden CSS bestanden..."
                curl -s https://api.github.com/repos/sandersmale/logger/contents/static/css | grep -o "\"download_url\": \"[^\"]*\"" | cut -d"\"" -f4 | while read url; do
                    wget -q -P static/css "$url" || log_error "Kan CSS bestand niet downloaden: $url"
                done
                ;;
            "static/js")
                log_info "Downloaden JavaScript bestanden..."
                curl -s https://api.github.com/repos/sandersmale/logger/contents/static/js | grep -o "\"download_url\": \"[^\"]*\"" | cut -d"\"" -f4 | while read url; do
                    wget -q -P static/js "$url" || log_error "Kan JavaScript bestand niet downloaden: $url"
                done
                ;;
        esac
    done
fi

# Stap 4: Controleer of benodigde pakketten zijn geïnstalleerd
PACKAGES=("python3" "python3-venv" "python3-pip" "ffmpeg" "apache2" "libapache2-mod-wsgi-py3" 
          "postgresql" "postgresql-contrib" "libpq-dev")
MISSING_PACKAGES=()

log_info "Controleren van benodigde pakketten..."

for pkg in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "$pkg"; then
        log_error "Vereist pakket ontbreekt: $pkg"
        MISSING_PACKAGES+=("$pkg")
    else
        log_info "Pakket geïnstalleerd: $pkg"
    fi
done

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    log_error "Vereiste pakketten ontbreken. Proberen te installeren..."
    apt update
    apt install -y ${MISSING_PACKAGES[@]} || {
        log_error "Kan niet alle vereiste pakketten installeren. Installatie kan niet doorgaan."
        log_error "Ontbrekende pakketten: ${MISSING_PACKAGES[*]}"
        exit 1
    }
    log_success "Alle vereiste pakketten succesvol geïnstalleerd"
fi

# Stap 5: Controleer of Apache modules zijn geactiveerd
APACHE_MODULES=("proxy" "proxy_http" "ssl" "rewrite" "headers")
MISSING_MODULES=()

log_info "Controleren van Apache modules..."

for module in "${APACHE_MODULES[@]}"; do
    if ! apache2ctl -M 2>/dev/null | grep -q "$module"; then
        log_error "Vereiste Apache module niet geactiveerd: $module"
        MISSING_MODULES+=("$module")
    else
        log_info "Apache module geactiveerd: $module"
    fi
done

if [ ${#MISSING_MODULES[@]} -gt 0 ]; then
    log_error "Vereiste Apache modules niet geactiveerd. Activeren..."
    for module in "${MISSING_MODULES[@]}"; do
        a2enmod "$module" || {
            log_error "Kan Apache module $module niet activeren. Installatie kan niet doorgaan."
            exit 1
        }
    done
    systemctl restart apache2
    log_success "Alle vereiste Apache modules succesvol geactiveerd"
fi

# Nu beginnen we met de daadwerkelijke installatie
log_info "Alle voorcontroles geslaagd of hersteld. Start installatie..."

# Stap 6: Maak applicatiemappen aan
INSTALL_DIR="/opt/radiologger"
LOG_DIR="/var/log/radiologger"
RECORDINGS_DIR="/var/lib/radiologger/recordings"

log_info "Aanmaken van applicatiemappen..."

mkdir -p "$INSTALL_DIR" || { log_error "Kan $INSTALL_DIR niet aanmaken"; exit 1; }
mkdir -p "$LOG_DIR" || { log_error "Kan $LOG_DIR niet aanmaken"; exit 1; }
mkdir -p "$RECORDINGS_DIR" || { log_error "Kan $RECORDINGS_DIR niet aanmaken"; exit 1; }

# Stap 7: Kopieer bestanden naar installatiemap
log_info "Kopiëren van bestanden naar installatiemap..."
cp -R . "$INSTALL_DIR/" || { log_error "Kan bestanden niet kopiëren naar $INSTALL_DIR"; exit 1; }

# Stap 8: Installeer Python venv en dependencies
log_info "Installeren van Python dependencies..."
cd "$INSTALL_DIR" || { log_error "Kan niet naar $INSTALL_DIR navigeren"; exit 1; }
python3 -m venv venv || { log_error "Kan Python venv niet aanmaken"; exit 1; }
source venv/bin/activate || { log_error "Kan venv niet activeren"; exit 1; }
pip install --upgrade pip || { log_error "Kan pip niet upgraden"; exit 1; }

# Maak requirements.txt als deze niet bestaat of update bestaande requirements.txt
log_info "Controleren of requirements.txt compatibel is met Flask en SQLAlchemy..."
if [ ! -f "requirements.txt" ] || grep -q "Flask==2.0.1" "requirements.txt"; then
    log_info "requirements.txt bestand ontbreekt of bevat incompatibele versies, bijwerken..."
    cat > requirements.txt << EOF
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
    log_success "requirements.txt compatibel gemaakt en bijgewerkt"
fi

# Ubuntu 24.04 vereist --break-system-packages flag
if grep -q "Ubuntu 24" /etc/os-release 2>/dev/null; then
    log_info "Ubuntu 24.04 gedetecteerd, gebruik --break-system-packages flag voor pip..."
    pip install -r requirements.txt --break-system-packages || { log_error "Kan vereiste Python packages niet installeren"; exit 1; }
else
    pip install -r requirements.txt || { log_error "Kan vereiste Python packages niet installeren"; exit 1; }
fi
# Ubuntu 24.04 vereist --break-system-packages flag
if grep -q "Ubuntu 24" /etc/os-release 2>/dev/null; then
    log_info "Ubuntu 24.04 gedetecteerd, gebruik --break-system-packages flag voor pip..."
    pip install gunicorn psycopg2-binary --break-system-packages || { log_error "Kan gunicorn of psycopg2 niet installeren"; exit 1; }
else
    pip install gunicorn psycopg2-binary || { log_error "Kan gunicorn of psycopg2 niet installeren"; exit 1; }
fi
deactivate

# Stap 9: PostgreSQL setup
log_info "PostgreSQL database setup..."
DB_USER="radiologger"
DB_NAME="radiologger"

# Controleer PostgreSQL installatie
if ! systemctl is-active --quiet postgresql; then
    log_warning "PostgreSQL service is niet actief. Starten..."
    systemctl start postgresql || handle_critical_error "Kan PostgreSQL service niet starten" 2
    sleep 3
fi

if ! systemctl is-active --quiet postgresql; then
    handle_critical_error "PostgreSQL service kon niet worden gestart. Controleer PostgreSQL installatie." 2
fi

# Genereer een random wachtwoord voor de database user
DB_PASS=$(openssl rand -hex 12)

# Controleer PostgreSQL authenticatiemethode en pas aan indien nodig
PG_HBA=$(sudo -u postgres psql -t -c "SHOW hba_file" | tr -d '[:space:]')
if [ -f "$PG_HBA" ]; then
    log_info "Controleren PostgreSQL authenticatiemethode in $PG_HBA..."
    # Voeg md5 authenticatie toe voor lokale verbindingen als deze nog niet bestaat
    if ! grep -q "host.*$DB_USER.*md5" "$PG_HBA"; then
        echo "host    $DB_NAME    $DB_USER    127.0.0.1/32    md5" | sudo tee -a "$PG_HBA" > /dev/null
        echo "host    $DB_NAME    $DB_USER    ::1/128         md5" | sudo tee -a "$PG_HBA" > /dev/null
        systemctl reload postgresql
        log_info "PostgreSQL configuratie aangepast voor md5 authenticatie"
    fi
fi

# Database gebruiker aanmaken (als die nog niet bestaat)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" || { 
        log_error "Kan database user niet aanmaken"
        log_info "Alternatieve methode proberen..."
        # Alternatieve methode met createuser commando
        sudo -u postgres createuser -P -d $DB_USER <<< "$DB_PASS
$DB_PASS" || handle_critical_error "Kan database user $DB_USER niet aanmaken met beide methoden" 3
    }
    log_info "Database gebruiker $DB_USER aangemaakt"
else
    log_info "Database gebruiker $DB_USER bestaat al"
    # Update het wachtwoord voor de bestaande gebruiker
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" || {
        log_error "Kan wachtwoord voor database user niet updaten via SQL"
        # Alternatieve methode met wachtwoord bestand
        echo "$DB_PASS" > /tmp/pg_pwd_tmp
        sudo -u postgres psql -c "\\password $DB_USER" < /tmp/pg_pwd_tmp 2>/dev/null
        rm -f /tmp/pg_pwd_tmp
    }
    
    # Zorg ervoor dat de gebruiker de juiste rechten heeft
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH CREATEDB;" || log_warning "Kan CREATEDB recht niet toewijzen aan $DB_USER"
fi

# Database aanmaken (als die nog niet bestaat)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" || {
        log_error "Kan database niet aanmaken via SQL"
        # Alternatieve methode met createdb commando
        sudo -u postgres createdb -O $DB_USER $DB_NAME || handle_critical_error "Kan database $DB_NAME niet aanmaken met beide methoden" 3
    }
    log_info "Database $DB_NAME aangemaakt"
else
    log_info "Database $DB_NAME bestaat al, controleren eigenaar..."
    # Controleer en pas eigenaar aan indien nodig
    DB_OWNER=$(sudo -u postgres psql -tAc "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname = '$DB_NAME';" | tr -d '[:space:]')
    if [ "$DB_OWNER" != "$DB_USER" ]; then
        log_warning "Database $DB_NAME heeft verkeerde eigenaar: $DB_OWNER, aanpassen naar $DB_USER..."
        sudo -u postgres psql -c "ALTER DATABASE $DB_NAME OWNER TO $DB_USER;" || log_warning "Kan eigenaar van database niet wijzigen"
    fi
fi

# Test database connectie
log_info "Testen database connectie..."
if PGPASSWORD="$DB_PASS" psql -h localhost -U $DB_USER -d $DB_NAME -c "\conninfo" > /dev/null 2>&1; then
    log_success "Database connectie succesvol getest"
else
    log_warning "Database connectietest mislukt. Installatie gaat door, maar controleer de PostgreSQL configuratie."
fi

# Stap 10: Vraag Wasabi S3 credentials en maak .env bestand aan
log_info "Configureren van Wasabi S3 opslag..."

# Vraag Wasabi informatie
echo -e "\n===== Wasabi S3 Storage Configuratie ====="
echo "Deze gegevens zijn nodig om opnames op te slaan in de cloud."
echo "Je kunt de credentials later wijzigen in het .env bestand."

read -p "Wasabi Access Key: " WASABI_ACCESS_KEY
read -p "Wasabi Secret Key: " WASABI_SECRET_KEY
read -p "Wasabi Bucket Naam: " WASABI_BUCKET
read -p "Wasabi Regio [default: eu-central-1]: " WASABI_REGION
WASABI_REGION=${WASABI_REGION:-eu-central-1}
WASABI_ENDPOINT_URL="https://s3.$WASABI_REGION.wasabisys.com"

# Controleer S3 toegang als credentials zijn opgegeven
if [ ! -z "$WASABI_ACCESS_KEY" ] && [ ! -z "$WASABI_SECRET_KEY" ] && [ ! -z "$WASABI_BUCKET" ]; then
    log_info "Testen van Wasabi S3 connectie..."
    
    # Activeer venv voor boto3 import
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    # Test S3 verbinding met Python
    python3 -c "
import boto3
import sys
try:
    s3 = boto3.client('s3', 
        endpoint_url='$WASABI_ENDPOINT_URL',
        aws_access_key_id='$WASABI_ACCESS_KEY',
        aws_secret_access_key='$WASABI_SECRET_KEY',
        region_name='$WASABI_REGION'
    )
    buckets = s3.list_buckets()
    bucket_exists = False
    for bucket in buckets['Buckets']:
        if bucket['Name'] == '$WASABI_BUCKET':
            bucket_exists = True
            break
    if not bucket_exists:
        print('Waarschuwing: Bucket $WASABI_BUCKET niet gevonden in je account')
        sys.exit(1)
    else:
        print('Verbinding met Wasabi S3 succesvol getest')
        sys.exit(0)
except Exception as e:
    print(f'Fout bij verbinden met Wasabi: {str(e)}')
    sys.exit(1)
" > /tmp/s3_test_output.txt 2>&1
    
    S3_TEST_RESULT=$?
    deactivate
    
    if [ $S3_TEST_RESULT -eq 0 ]; then
        log_success "Wasabi S3 verbinding succesvol getest"
    else
        log_warning "Kon geen verbinding maken met Wasabi S3. Zie /tmp/s3_test_output.txt voor details."
        cat /tmp/s3_test_output.txt
        log_warning "De installatie gaat door, maar opnames worden lokaal opgeslagen totdat S3 correct is geconfigureerd."
    fi
else
    log_warning "Wasabi S3 credentials niet volledig ingevuld. Opnames worden lokaal opgeslagen."
    log_warning "Je kunt de S3 configuratie later toevoegen in /opt/radiologger/.env"
fi

log_info "Aanmaken .env bestand..."
cat > "$INSTALL_DIR/.env" << EOF
FLASK_APP=main.py
FLASK_ENV=production
FLASK_SECRET_KEY=$(openssl rand -hex 24)
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@localhost/$DB_NAME
LOGS_DIR=$LOG_DIR
RECORDINGS_DIR=$RECORDINGS_DIR

# Wasabi S3 configuratie
WASABI_ACCESS_KEY=$WASABI_ACCESS_KEY
WASABI_SECRET_KEY=$WASABI_SECRET_KEY
WASABI_BUCKET=$WASABI_BUCKET  
WASABI_REGION=$WASABI_REGION
WASABI_ENDPOINT_URL=$WASABI_ENDPOINT_URL

# Lokale retentie (in uren, 0 = direct na upload verwijderen)
LOCAL_FILE_RETENTION=0
EOF

log_info ".env bestand aangemaakt met Wasabi configuratie"

# Stap 11: Configureer Apache
log_info "Apache configuratie..."
read -p "Wat is de domeinnaam voor deze server? (bijv. logger.pilotradio.nl, laat leeg voor alleen IP): " DOMAIN_NAME
read -p "Wat is je email adres voor SSL certificaten? (laat leeg om SSL over te slaan): " EMAIL

# Kopieer Apache configuratiebestand
cp "$INSTALL_DIR/radiologger_apache.conf" /etc/apache2/sites-available/ || { log_error "Kan Apache configuratie niet kopiëren"; exit 1; }

# Bewerk de Apache config om de domeinnaam in te stellen als die is opgegeven
if [ ! -z "$DOMAIN_NAME" ]; then
    sed -i "s/ServerName example.com/ServerName $DOMAIN_NAME/g" /etc/apache2/sites-available/radiologger_apache.conf
    log_info "Domeinnaam $DOMAIN_NAME ingesteld in Apache configuratie"
fi

# Schakel de site in
a2ensite radiologger_apache.conf || { log_error "Kan site niet inschakelen"; exit 1; }

# SSL certificaat installeren als er een domeinnaam en email is opgegeven
if [ ! -z "$DOMAIN_NAME" ] && [ ! -z "$EMAIL" ]; then
    log_info "Installeren SSL certificaat voor $DOMAIN_NAME..."
    certbot --apache -d $DOMAIN_NAME --non-interactive --agree-tos --email $EMAIL || log_error "SSL certificaat kon niet automatisch worden geïnstalleerd"
else
    log_info "SSL configuratie overgeslagen (geen domeinnaam of email opgegeven)"
fi

# Herstart Apache
systemctl restart apache2 || { log_error "Kan Apache niet herstarten"; exit 1; }

# Stap 12: Systemd service installeren
log_info "Systemd service installeren..."
if [ -f "$INSTALL_DIR/radiologger.service" ]; then
    # Backup originele service file
    cp "$INSTALL_DIR/radiologger.service" "$INSTALL_DIR/radiologger.service.orig"
    
    # Controleer en bewerk de HOME directory in het service bestand
    if ! grep -q "Environment=\"HOME=" "$INSTALL_DIR/radiologger.service"; then
        log_info "HOME environment toevoegen aan service file..."
        # Voeg HOME environment toe tussen [Service] en ExecStart
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' "$INSTALL_DIR/radiologger.service"
    fi
    
    # Controleer WorkingDirectory
    if ! grep -q "WorkingDirectory=" "$INSTALL_DIR/radiologger.service"; then
        log_info "WorkingDirectory toevoegen aan service file..."
        sed -i '/\[Service\]/a WorkingDirectory=/opt/radiologger' "$INSTALL_DIR/radiologger.service"
    fi
    
    # Installeer service
    cp "$INSTALL_DIR/radiologger.service" /etc/systemd/system/ || { 
        log_error "Kan systemd service niet kopiëren" 
        # Herstelpoging met origineel bestand
        cp "$INSTALL_DIR/radiologger.service.orig" /etc/systemd/system/ || handle_critical_error "Kan service file niet installeren" 4
    }
    
    # Laad systemd daemon opnieuw
    systemctl daemon-reload || { log_error "Kan systemd daemon niet herladen"; exit 1; }
    
    # Schakel service in
    systemctl enable radiologger || { log_error "Kan radiologger service niet inschakelen"; exit 1; }
    
    log_success "Systemd service succesvol geïnstalleerd en ingeschakeld"
else
    # Als het bestand ontbreekt, genereer een nieuw service bestand
    log_warning "radiologger.service bestand ontbreekt, genereren..."
    
    cat > "$INSTALL_DIR/radiologger.service" << EOF
[Unit]
Description=Radiologger Radio Recording Service
After=network.target postgresql.service
Wants=postgresql.service

[Service]
User=radiologger
Group=radiologger
WorkingDirectory=/opt/radiologger
Environment="HOME=/opt/radiologger"
ExecStart=/opt/radiologger/venv/bin/gunicorn --bind 0.0.0.0:5000 --workers 2 main:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    cp "$INSTALL_DIR/radiologger.service" /etc/systemd/system/ || handle_critical_error "Kan gegenereerde service file niet installeren" 4
    systemctl daemon-reload || handle_critical_error "Kan systemd daemon niet herladen" 4
    systemctl enable radiologger || handle_critical_error "Kan radiologger service niet inschakelen" 4
    
    log_success "Systemd service succesvol gegenereerd en geïnstalleerd"
fi

# Stap 13: Gebruiker aanmaken en rechten instellen
log_info "Gebruiker aanmaken en rechten instellen..."
# Controleer of de gebruiker al bestaat
if ! id -u radiologger &>/dev/null; then
    useradd -r -s /bin/false radiologger || { log_error "Kan radiologger gebruiker niet aanmaken"; exit 1; }
    log_info "Gebruiker radiologger aangemaakt"
else
    log_info "Gebruiker radiologger bestaat al"
fi

# Zet permissies goed
chown -R radiologger:radiologger "$INSTALL_DIR" || { log_error "Kan eigenaar van $INSTALL_DIR niet wijzigen"; exit 1; }
chown -R radiologger:radiologger "$LOG_DIR" || { log_error "Kan eigenaar van logs niet wijzigen"; exit 1; }
chown -R radiologger:radiologger /var/lib/radiologger || { log_error "Kan eigenaar van recordings niet wijzigen"; exit 1; }

find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
find "$INSTALL_DIR" -name "*.sh" -exec chmod 755 {} \;

# Stap 14: Initialiseer database
log_info "Database initialiseren..."
cd "$INSTALL_DIR" || { log_error "Kan niet naar $INSTALL_DIR navigeren"; exit 1; }
sudo -u radiologger bash -c "cd $INSTALL_DIR && source venv/bin/activate && python init_db.py" || log_error "Waarschuwing: Kon database niet initialiseren"

# Stap 15: Start de service
log_info "Radiologger service starten..."
systemctl start radiologger
if ! systemctl is-active --quiet radiologger; then
    log_warning "Radiologger service kon niet gestart worden, proberen te debuggen..."
    
    # Controleer logs
    journalctl -u radiologger --no-pager -n 20 >> "$ERROR_LOG"
    
    # Controleer Python executable
    if [ ! -f "$INSTALL_DIR/venv/bin/python" ]; then
        log_error "Python executable niet gevonden in venv"
        # Herstelpoging voor venv
        cd "$INSTALL_DIR"
        rm -rf venv
        python3 -m venv venv
        source venv/bin/activate
        # Ubuntu 24.04 vereist --break-system-packages flag
        if grep -q "Ubuntu 24" /etc/os-release 2>/dev/null; then
            log_info "Ubuntu 24.04 gedetecteerd, gebruik --break-system-packages flag voor pip..."
            pip install -r requirements.txt --break-system-packages
        else
            pip install -r requirements.txt
        fi
        deactivate
    fi
    
    # Controleer gunicorn executable
    if [ ! -f "$INSTALL_DIR/venv/bin/gunicorn" ]; then
        log_error "Gunicorn executable niet gevonden in venv"
        source "$INSTALL_DIR/venv/bin/activate"
        # Ubuntu 24.04 vereist --break-system-packages flag
        if grep -q "Ubuntu 24" /etc/os-release 2>/dev/null; then
            log_info "Ubuntu 24.04 gedetecteerd, gebruik --break-system-packages flag voor pip..."
            pip install gunicorn --break-system-packages
        else
            pip install gunicorn
        fi
        deactivate
    fi
    
    # Controleer bestandspermissies
    log_info "Herstellen permissies..."
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -name "*.sh" -exec chmod 755 {} \;
    find "$INSTALL_DIR" -name "*.py" -exec chmod 644 {} \;
    chmod 755 "$INSTALL_DIR/venv/bin/python" "$INSTALL_DIR/venv/bin/gunicorn" 2>/dev/null
    
    # Probeer de service opnieuw te starten
    systemctl restart radiologger
    sleep 3
    
    if ! systemctl is-active --quiet radiologger; then
        log_warning "Radiologger service kon nog steeds niet gestart worden. Zie logs voor details."
        echo "Controleer handmatig met 'sudo journalctl -u radiologger' na installatie."
    else
        log_success "Radiologger service succesvol gestart na debug en herstel!"
    fi
else
    log_success "Radiologger service succesvol gestart!"
fi

# Stap 16: Toon samenvatting
echo "====================================================================="
echo "          Radiologger Installatie Voltooid!"
echo "====================================================================="

echo "Belangrijke informatie:"
echo "Database gebruiker: $DB_USER"
echo "Database naam: $DB_NAME"
echo "Database wachtwoord: $DB_PASS"
echo ""
echo "Applicatiemap: $INSTALL_DIR"
echo "Log bestanden: $LOG_DIR"
echo "Opnames map: $RECORDINGS_DIR"
echo ""
if [ ! -z "$DOMAIN_NAME" ]; then
    echo "WebUI: https://$DOMAIN_NAME"
else
    echo "WebUI: http://<server-ip>"
fi
echo ""
echo "Bij de eerste keer openen van de WebUI, zal je worden gevraagd om:"
echo "1. Een administrator account aan te maken"
echo "2. Wasabi S3 opslag te configureren"
echo ""
echo "Controleer de status met:"
echo "  sudo systemctl status radiologger"
echo "  sudo systemctl status apache2"
echo ""
echo "Bekijk logs met:"
echo "  sudo tail -f $LOG_DIR/error.log"
echo "  sudo tail -f /var/log/apache2/error.log"
echo ""
echo "Bekijk installatie logs met:"
echo "  sudo cat $LOG_FILE"
echo "  sudo cat $ERROR_LOG"

log_success "Installatie succesvol afgerond!"