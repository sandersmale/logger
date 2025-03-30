#!/bin/bash
# find_env_issues.sh
# Dit script controleert de omgevingsvariabelen en database connectiviteit
# voor de Radiologger applicatie.

set -e

# Kleuren voor output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Functies
function check_success() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $1"
    else
        echo -e "${RED}✗${NC} $1"
        if [ ! -z "$2" ]; then
            echo "$2"
        fi
    fi
}

function check_installed() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is geïnstalleerd"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is niet geïnstalleerd"
        return 1
    fi
}

# Heading
echo "=========== OMGEVINGSDIAGNOSE ==========="
echo "Huidige directory: $(pwd)"
echo "Huidige gebruiker: $(whoami)"
echo "Systeem: $(uname -a)"
echo

# Controleer database connectiviteit
echo "=========== DATABASE CONNECTIVITEIT ==========="
check_installed psql

# Controleer .env bestand
if [ -f ".env" ]; then
    echo -e "${GREEN}✓${NC} .env bestand gevonden"
    
    # Toon .env inhoud zonder wachtwoorden
    echo "--- .env inhoud (wachtwoorden verborgen) ---"
    cat -n .env | sed 's/\(.*PASSWORD=\|.*_KEY=\|.*Secret\).*$/\1****/'
    echo "---"
    
    # Extraheer database URL
    DB_URL=$(grep -E '^DATABASE_URL=' .env | cut -d '=' -f2-)
    
    if [ ! -z "$DB_URL" ]; then
        echo -e "${GREEN}✓${NC} DATABASE_URL gevonden in .env"
        
        # Parse de URL en toon onderdelen
        DB_TYPE=$(echo $DB_URL | cut -d ':' -f1)
        DB_REST=$(echo $DB_URL | sed 's/^[^:]*:\/\///')
        DB_USER=$(echo $DB_REST | cut -d ':' -f1)
        DB_HOST_PORT_NAME=$(echo $DB_REST | cut -d '@' -f2)
        
        echo "  - Database type: $DB_TYPE"
        echo "  - Database gebruiker: $DB_USER"
        
        # Toon host/port/naam
        if [[ $DB_HOST_PORT_NAME == *"/"* ]]; then
            DB_HOST=$(echo $DB_HOST_PORT_NAME | cut -d '/' -f1 | cut -d ':' -f1)
            DB_PORT=$(echo $DB_HOST_PORT_NAME | cut -d '/' -f1 | grep -o ':[0-9]*' | cut -d ':' -f2)
            DB_NAME=$(echo $DB_HOST_PORT_NAME | cut -d '/' -f2-)
            
            echo "  - Database host: $DB_HOST"
            if [ ! -z "$DB_PORT" ]; then
                echo "  - Database poort: $DB_PORT"
            fi
            echo "  - Database naam: $DB_REST"
        else
            echo "  - Database connectie-string: $DB_REST"
        fi
        
        # Test de connectie
        echo -e "\nTest verbinding met database..."
        if [[ $DB_URL == postgresql://* ]]; then
            # PostgreSQL test
            psql "$DB_URL" -c "SELECT 1" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓${NC} Verbinding met PostgreSQL database succesvol"
            else
                echo -e "${RED}✗${NC} Kan geen verbinding maken met de database"
                echo "PostgreSQL foutmelding:"
                psql "$DB_URL" -c "SELECT 1" 2>&1 | grep -v "^psql: warning:"
            fi
        else
            echo -e "${YELLOW}⚠${NC} Geen PostgreSQL database, kan connectie niet testen"
        fi
    else
        echo -e "${RED}✗${NC} Geen DATABASE_URL gevonden in .env"
    fi
else
    echo -e "${RED}✗${NC} Geen .env bestand gevonden"
fi

echo
echo "=========== PYTHON OMGEVING ==========="
echo "Python versie:"
python3 --version

echo -e "\nPython path:"
python3 -c "import sys; print(sys.path)"

echo -e "\nGeïnstalleerde packages:"
pip3 list 2>/dev/null || echo "pip3 command niet beschikbaar"

echo -e "\nWerkend directory inhoud:"
ls -la | head -30

# Controleer applicatie bestanden
echo -e "\n=========== APPLICATIE BESTANDEN ==========="
REQUIRED_FILES=("app.py" "config.py" "models.py" "main.py")

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file gevonden"
    else
        echo -e "${RED}✗${NC} $file niet gevonden"
    fi
done

# Fix database wachtwoord als autofix geselecteerd is
echo ""
echo "Wil je automatisch de database verbinding proberen te repareren? (j/n)"
read -p "> " auto_fix_db

if [[ "$auto_fix_db" =~ ^[jJ]$ ]]; then
    echo "Vereenvoudigd database wachtwoord aanmaken en verbinding herstellen..."
    if command -v psql &> /dev/null; then
        sudo -u postgres psql -c "ALTER USER radiologger WITH PASSWORD 'Radiologger2024!';"
        
        # Update het wachtwoord in de .env file
        if [ -f ".env" ]; then
            sed -i 's|DATABASE_URL=postgresql://radiologger:.*@localhost|DATABASE_URL=postgresql://radiologger:Radiologger2024!@localhost|' .env
            echo -e "${GREEN}✓${NC} Database wachtwoord gereset naar 'Radiologger2024!' en .env bestand bijgewerkt"
            
            # Herstart services
            echo "Radiologger service herstarten..."
            if command -v systemctl &> /dev/null; then
                systemctl restart radiologger
                echo "Nginx herstarten..."
                systemctl restart nginx
                
                # Toon status
                echo ""
                echo "Service status na fix:"
                systemctl status radiologger --no-pager -n 5
            else
                echo -e "${YELLOW}⚠${NC} systemctl niet beschikbaar, kan services niet herstarten"
            fi
        else
            echo -e "${RED}✗${NC} Kon .env bestand niet vinden om het wachtwoord bij te werken"
        fi
    else
        echo -e "${RED}✗${NC} psql command niet beschikbaar, kan database niet updaten"
    fi
fi

# Controleer en maak main.py bestand indien nodig
if [ ! -f "main.py" ]; then
    echo -e "\nHet 'main.py' bestand ontbreekt. Wil je dit automatisch aanmaken? (j/n)"
    read -p "> " create_main
    
    if [[ "$create_main" =~ ^[jJ]$ ]]; then
        cat > main.py << 'EOL'
import os
import logging
from flask import Flask

# Configureer logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('app')

# create the app
app = Flask(__name__)

# setup a secret key
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "development-key-replace-in-production")

# configureer de database
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get("DATABASE_URL")
app.config["SQLALCHEMY_ENGINE_OPTIONS"] = {
    "pool_recycle": 300,
    "pool_pre_ping": True,
}

# Log de database URL (verberg wachtwoord voor veiligheid)
db_url = os.environ.get("DATABASE_URL", "")
if db_url:
    parts = db_url.split('@')
    if len(parts) > 1:
        credential_parts = parts[0].split(':')
        if len(credential_parts) > 2:
            masked_url = f"{credential_parts[0]}:****@{parts[1]}"
            logger.info(f"App configuratie geladen. Database: {masked_url}")

# Importeer app.py (de echte app definitie)
from app import app as flask_app

# Deze import moet na app.py komen om circulaire imports te voorkomen
import routes

# Alleen voor lokale ontwikkeling
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
EOL
        chmod 755 main.py
        echo -e "${GREEN}✓${NC} main.py bestand succesvol aangemaakt"
        
        # Herstart de service indien beschikbaar
        if command -v systemctl &> /dev/null; then
            echo "Radiologger service herstarten..."
            systemctl restart radiologger
        fi
    fi
fi

echo
echo "Diagnose voltooid."
echo "Als er problemen zijn gedetecteerd, voer 'fix_permissions.sh' uit om algemene permissie-issues op te lossen."