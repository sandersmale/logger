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

echo
echo "Diagnose voltooid."