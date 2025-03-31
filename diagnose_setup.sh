#!/bin/bash
#
# Diagnose setup pagina problemen
# Dit script diagnosticeert en lost problemen op met de setup pagina

# Kleuren en stijlen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Functie voor headers
header() {
    echo -e "\n${BLUE}${BOLD}$1${NC}"
    echo -e "${BLUE}${BOLD}$(printf '=%.0s' $(seq 1 ${#1}))${NC}\n"
}

# Functie voor status berichten
log_info() {
    echo -e "[${BLUE}INFO${NC}] $1"
}

log_success() {
    echo -e "[${GREEN}OK${NC}] $1"
}

log_warning() {
    echo -e "[${YELLOW}WAARSCHUWING${NC}] $1"
}

log_error() {
    echo -e "[${RED}FOUT${NC}] $1"
}

# Controleer root toegang
if [[ $EUID -ne 0 ]]; then
   log_error "Dit script moet uitgevoerd worden als root (sudo)"
   exit 1
fi

header "Radiologger Setup Pagina Diagnose"

# Controleer applicatiemap
if [ ! -d "/opt/radiologger" ]; then
    log_error "Radiologger installatiemap niet gevonden in /opt/radiologger"
    exit 1
fi

# Controleer database connectie
log_info "Database verbinding controleren..."
cd /opt/radiologger

# Controleer of de database URL is ingesteld
if grep -q "DATABASE_URL" /opt/radiologger/.env; then
    log_success "DATABASE_URL gevonden in .env bestand"
else
    log_error "DATABASE_URL niet gevonden in .env bestand"
    exit 1
fi

# Controleer gebruikers in database
log_info "Gebruikers in database controleren..."
source /opt/radiologger/venv/bin/activate

# Activeer Python virtuele omgeving en controleer gebruikers
output=$(sudo -u radiologger bash -c "cd /opt/radiologger && source venv/bin/activate && python -c 'from app import app, db; from models import User; import sys; 
with app.app_context(): 
    count = User.query.count();
    print(f\"Gevonden gebruikers: {count}\");
    sys.exit(0 if count == 0 else 1)'")

user_exit_code=$?
echo "$output"

if [ $user_exit_code -eq 0 ]; then
    log_success "Geen gebruikers gevonden in database. Setup pagina zou moeten verschijnen."
else
    log_warning "Gebruikers gevonden in database. Setup pagina zal niet verschijnen."
    
    # Vraag om bevestiging voor reset
    read -p "Wil je alle gebruikers verwijderen om de setup pagina te forceren? (j/n): " answer
    if [[ "$answer" == "j" || "$answer" == "J" ]]; then
        log_info "Gebruikers verwijderen..."
        sudo -u radiologger bash -c "cd /opt/radiologger && source venv/bin/activate && python reset_users.py"
        
        if [ $? -eq 0 ]; then
            log_success "Gebruikers succesvol verwijderd. De setup pagina zou nu moeten verschijnen."
        else
            log_error "Kon gebruikers niet verwijderen."
        fi
    else
        log_info "Geen gebruikers verwijderd."
    fi
fi

# Controleer service status
log_info "Radiologger service status controleren..."
if systemctl is-active --quiet radiologger; then
    log_success "Radiologger service is actief"
else
    log_warning "Radiologger service is niet actief. Service herstarten..."
    systemctl restart radiologger
    
    if systemctl is-active --quiet radiologger; then
        log_success "Radiologger service succesvol herstart"
    else
        log_error "Kon Radiologger service niet herstarten. Probeer 'sudo journalctl -u radiologger' voor meer details."
    fi
fi

# Controleer Apache configuratie
log_info "Apache configuratie controleren..."
if [ -f "/etc/apache2/sites-enabled/radiologger.conf" ]; then
    log_success "Radiologger Apache configuratie is ingeschakeld"
else
    log_warning "Radiologger Apache configuratie is niet ingeschakeld. Configuratie herstellen..."
    
    # Controleer of fix script bestaat
    if [ -f "/opt/radiologger/fix_apache_config.sh" ]; then
        bash /opt/radiologger/fix_apache_config.sh
        
        if [ -f "/etc/apache2/sites-enabled/radiologger.conf" ]; then
            log_success "Apache configuratie succesvol hersteld"
        else
            log_error "Kon Apache configuratie niet herstellen"
        fi
    else
        log_error "fix_apache_config.sh script niet gevonden"
    fi
fi

# Controleer poort 5000
log_info "Controleren of poort 5000 in gebruik is..."
if netstat -tuln | grep -q ":5000 "; then
    log_success "Poort 5000 is in gebruik (applicatie draait)"
else
    log_warning "Poort 5000 lijkt niet in gebruik te zijn. Probeer de service te herstarten."
    systemctl restart radiologger
    sleep 2
    
    if netstat -tuln | grep -q ":5000 "; then
        log_success "Poort 5000 is nu actief na herstart"
    else
        log_error "Poort 5000 is nog steeds niet actief na herstart"
    fi
fi

# Sluit af met instructies
header "Diagnose Voltooid"
echo -e "Als je nog steeds de setup pagina niet ziet, probeer:"
echo -e "1. Ververs je browser cache (Ctrl+F5)"
echo -e "2. Probeer een andere browser"
echo -e "3. Controleer of je naar het juiste adres navigeert"
echo -e "   - Met domein: https://jouw-domein.nl"
echo -e "   - Zonder domein: http://server-ip:5000"
echo -e ""
echo -e "Voor meer hulp, raadpleeg de documentatie in /opt/radiologger/EERSTE_GEBRUIK.md"