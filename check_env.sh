#!/bin/bash
# Controleer en corrigeer het .env bestand
# Dit script controleert of alle benodigde omgevingsvariabelen aanwezig zijn

echo "Radiologger .env Check Script"
echo "==========================="
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

ENV_FILE="/opt/radiologger/.env"

# Controleer of .env bestand bestaat
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ .env bestand niet gevonden op pad: $ENV_FILE"
    echo "Wil je een nieuw .env bestand aanmaken met standaardwaarden? (j/n)"
    read -r CREATE_ENV
    
    if [[ "$CREATE_ENV" =~ ^[jJ]$ ]]; then
        echo "Aanmaken van nieuw .env bestand..."
        
        # Maak directory indien nodig
        mkdir -p $(dirname "$ENV_FILE")
        
        # .env bestand aanmaken met standaardwaarden
        cat > "$ENV_FILE" << EOL
# Radiologger configuratie
# Aangemaakt door check_env.sh op $(date)

# Flask configuratie
FLASK_APP=main.py
FLASK_ENV=production
FLASK_SECRET_KEY=$(openssl rand -hex 24)

# Database configuratie
DATABASE_URL=postgresql://radiologger:password@localhost/radiologger

# Logging
LOG_LEVEL=INFO
LOGS_DIR=/var/log/radiologger

# Opnames
RECORDINGS_DIR=/var/lib/radiologger/recordings
RETENTION_DAYS=30
LOCAL_FILE_RETENTION=24

# Wasabi/S3 configuratie
WASABI_ACCESS_KEY=your_access_key
WASABI_SECRET_KEY=your_secret_key
WASABI_BUCKET=your_bucket_name
WASABI_REGION=eu-central-1
WASABI_ENDPOINT_URL=https://s3.eu-central-1.wasabisys.com

# Externe API's
OMROEP_LVC_URL=https://gemist.omroeplvc.nl/
DENNIS_API_URL=https://logger.dennishoogeveenmedia.nl/api/stations.json

# FFMPEG
FFMPEG_PATH=/usr/bin/ffmpeg
EOL
        
        # Set permissions
        chown radiologger:radiologger "$ENV_FILE"
        chmod 640 "$ENV_FILE"
        
        echo "✅ Standaard .env bestand aangemaakt"
        echo "⚠️ Pas dit bestand aan met je eigen instellingen: sudo nano $ENV_FILE"
    else
        echo "❌ Geen .env bestand aangemaakt. Radiologger zal niet correct werken zonder dit bestand."
        exit 1
    fi
else
    echo "✅ .env bestand gevonden, inhoud controleren..."
    
    # Controleer of alle benodigde variabelen aanwezig zijn
    MISSING_VARS=()
    
    # Lijst van essentiële variabelen
    REQUIRED_VARS=(
        "FLASK_APP"
        "FLASK_SECRET_KEY"
        "DATABASE_URL"
        "LOGS_DIR"
        "RECORDINGS_DIR"
        "WASABI_ACCESS_KEY"
        "WASABI_SECRET_KEY"
        "WASABI_BUCKET"
        "WASABI_REGION"
        "WASABI_ENDPOINT_URL"
        "FFMPEG_PATH"
    )
    
    # Controleer elke variabele
    for VAR in "${REQUIRED_VARS[@]}"; do
        if ! grep -q "^$VAR=" "$ENV_FILE"; then
            MISSING_VARS+=("$VAR")
        fi
    done
    
    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo "⚠️ Ontbrekende variabelen gevonden in .env bestand:"
        for VAR in "${MISSING_VARS[@]}"; do
            echo "   - $VAR"
        done
        
        echo "Wil je deze variabelen toevoegen met standaardwaarden? (j/n)"
        read -r ADD_VARS
        
        if [[ "$ADD_VARS" =~ ^[jJ]$ ]]; then
            echo "Variabelen toevoegen..."
            
            # Voeg ontbrekende variabelen toe
            for VAR in "${MISSING_VARS[@]}"; do
                case "$VAR" in
                    "FLASK_APP")
                        echo "FLASK_APP=main.py" >> "$ENV_FILE"
                        ;;
                    "FLASK_SECRET_KEY")
                        echo "FLASK_SECRET_KEY=$(openssl rand -hex 24)" >> "$ENV_FILE"
                        ;;
                    "DATABASE_URL")
                        echo "DATABASE_URL=postgresql://radiologger:password@localhost/radiologger" >> "$ENV_FILE"
                        ;;
                    "LOGS_DIR")
                        echo "LOGS_DIR=/var/log/radiologger" >> "$ENV_FILE"
                        ;;
                    "RECORDINGS_DIR")
                        echo "RECORDINGS_DIR=/var/lib/radiologger/recordings" >> "$ENV_FILE"
                        ;;
                    "WASABI_ACCESS_KEY")
                        echo "WASABI_ACCESS_KEY=your_access_key" >> "$ENV_FILE"
                        ;;
                    "WASABI_SECRET_KEY")
                        echo "WASABI_SECRET_KEY=your_secret_key" >> "$ENV_FILE"
                        ;;
                    "WASABI_BUCKET")
                        echo "WASABI_BUCKET=your_bucket_name" >> "$ENV_FILE"
                        ;;
                    "WASABI_REGION")
                        echo "WASABI_REGION=eu-central-1" >> "$ENV_FILE"
                        ;;
                    "WASABI_ENDPOINT_URL")
                        echo "WASABI_ENDPOINT_URL=https://s3.eu-central-1.wasabisys.com" >> "$ENV_FILE"
                        ;;
                    "FFMPEG_PATH")
                        echo "FFMPEG_PATH=/usr/bin/ffmpeg" >> "$ENV_FILE"
                        ;;
                esac
            done
            
            echo "✅ Ontbrekende variabelen toegevoegd"
            echo "⚠️ Pas de standaardwaarden aan naar je eigen instellingen: sudo nano $ENV_FILE"
        else
            echo "⚠️ Ontbrekende variabelen niet toegevoegd. Radiologger werkt mogelijk niet correct."
        fi
    else
        echo "✅ Alle benodigde variabelen zijn aanwezig in het .env bestand"
    fi
    
    # Controleer eigenaarschap en permissies
    OWNER=$(stat -c '%U:%G' "$ENV_FILE")
    if [ "$OWNER" != "radiologger:radiologger" ]; then
        echo "⚠️ Eigenaarschap van .env bestand is incorrect: $OWNER"
        echo "Aanpassen naar radiologger:radiologger..."
        chown radiologger:radiologger "$ENV_FILE"
    fi
    
    PERM=$(stat -c '%a' "$ENV_FILE")
    if [ "$PERM" != "640" ]; then
        echo "⚠️ Permissies van .env bestand zijn incorrect: $PERM"
        echo "Aanpassen naar 640..."
        chmod 640 "$ENV_FILE"
    fi
fi

# Controleer of venv bestaat
if [ ! -d "/opt/radiologger/venv" ]; then
    echo "❌ Python virtual environment niet gevonden"
    echo "Dit kan problemen veroorzaken met de service"
    echo "Herinstalleer de applicatie of maak een nieuwe venv aan"
else
    echo "✅ Python virtual environment gevonden"
fi

# Controleer services after any .env changes
echo "Services herstarten om wijzigingen toe te passen..."
systemctl restart radiologger
systemctl restart nginx

echo ""
echo "✅ .env check voltooid!"
echo "Als je nog steeds 502 Bad Gateway ziet, controleer of de configuratiewaarden correct zijn"
echo "sudo nano $ENV_FILE"