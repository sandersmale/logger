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

# Logfuncties
log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - FOUT: $1" | tee -a "$ERROR_LOG" >&2
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCES: $1" | tee -a "$LOG_FILE"
}

# Controleer of het script als root draait
if [ "$EUID" -ne 0 ]; then
    log_error "Dit script moet als root worden uitgevoerd. Gebruik 'sudo bash $0'"
    exit 1
fi

# Banner tonen
echo "====================================================================="
echo "          Radiologger - Betrouwbare Installatie"
echo "====================================================================="

# Stap 1: Controleer of we in de juiste directory zijn
CURRENT_DIR=$(pwd)
log_info "Huidige directory: $CURRENT_DIR"

# Stap 2: Controleer of essentiële bestanden aanwezig zijn
ESSENTIAL_FILES=("main.py" "app.py" "forms.py" "auth.py" "emergency_forms.py" "radiologger.service" "radiologger_apache.conf")
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
    
    for file in "${MISSING_FILES[@]}"; do
        log_info "Downloaden van ontbrekend bestand: $file"
        wget -q "https://raw.githubusercontent.com/sandersmale/logger/main/$file" || {
            log_error "Kan $file niet downloaden. Installatie kan niet doorgaan."
            exit 1
        }
        log_success "Bestand $file succesvol gedownload"
    done
fi

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

# Maak requirements.txt als deze niet bestaat
if [ ! -f "requirements.txt" ]; then
    log_info "requirements.txt bestand ontbreekt, maak aan met essentiële packages..."
    cat > requirements.txt << EOF
Flask==2.0.1
Flask-SQLAlchemy==3.0.3
Flask-Login==0.6.2
Flask-WTF==1.1.1
psycopg2-binary==2.9.5
gunicorn==21.2.0
APScheduler==3.10.1
boto3==1.28.3
python-dotenv==1.0.0
email-validator==2.0.0
WTForms==3.0.1
Werkzeug==2.2.3
SQLAlchemy==2.0.9
trafilatura==1.6.0
requests==2.31.0
psutil==5.9.0
EOF
    log_success "requirements.txt aangemaakt"
fi

pip install -r requirements.txt || { log_error "Kan vereiste Python packages niet installeren"; exit 1; }
pip install gunicorn psycopg2-binary || { log_error "Kan gunicorn of psycopg2 niet installeren"; exit 1; }
deactivate

# Stap 9: PostgreSQL setup
log_info "PostgreSQL database setup..."
DB_USER="radiologger"
DB_NAME="radiologger"

# Genereer een random wachtwoord voor de database user
DB_PASS=$(openssl rand -hex 12)

# Database gebruiker aanmaken (als die nog niet bestaat)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';" || { log_error "Kan database user niet aanmaken"; exit 1; }
    log_info "Database gebruiker $DB_USER aangemaakt"
else
    log_info "Database gebruiker $DB_USER bestaat al"
    # Update het wachtwoord voor de bestaande gebruiker
    sudo -u postgres psql -c "ALTER USER $DB_USER WITH PASSWORD '$DB_PASS';" || { log_error "Kan wachtwoord voor database user niet updaten"; exit 1; }
fi

# Database aanmaken (als die nog niet bestaat)
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" || { log_error "Kan database niet aanmaken"; exit 1; }
    log_info "Database $DB_NAME aangemaakt"
else
    log_info "Database $DB_NAME bestaat al"
fi

# Stap 10: Maak .env bestand aan
log_info "Aanmaken .env bestand..."
cat > "$INSTALL_DIR/.env" << EOF
FLASK_APP=main.py
FLASK_ENV=production
FLASK_SECRET_KEY=$(openssl rand -hex 24)
DATABASE_URL=postgresql://$DB_USER:$DB_PASS@localhost/$DB_NAME
LOGS_DIR=$LOG_DIR
RECORDINGS_DIR=$RECORDINGS_DIR
EOF

log_info ".env bestand aangemaakt"

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
    cp "$INSTALL_DIR/radiologger.service" /etc/systemd/system/ || { log_error "Kan systemd service niet kopiëren"; exit 1; }
    systemctl daemon-reload || { log_error "Kan systemd daemon niet herladen"; exit 1; }
    systemctl enable radiologger || { log_error "Kan radiologger service niet inschakelen"; exit 1; }
else
    log_error "radiologger.service bestand ontbreekt"
    exit 1
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
systemctl start radiologger || { log_error "Kan radiologger service niet starten"; exit 1; }

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