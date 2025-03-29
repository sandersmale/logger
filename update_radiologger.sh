#!/bin/bash
# Update script voor Radiologger
# Dit script werkt Radiologger bij vanaf GitHub

set -e  # Stop bij fouten

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd"
   exit 1
fi

echo "Radiologger update script"
echo "========================="
echo ""

# Vraag om bevestiging
echo "Dit script zal het volgende doen:"
echo "1. Git repository updaten"
echo "2. Dependencies updaten"
echo "3. Database migraties uitvoeren (indien nodig)"
echo "4. Diensten herstarten"
echo ""
echo "Wil je doorgaan? (j/n): "
read -r response
if [[ ! "$response" =~ ^[jJ]$ ]]; then
    echo "Update geannuleerd"
    exit 0
fi

echo ""
echo "Backup maken van de huidige configuratie..."
cp /opt/radiologger/.env /opt/radiologger/.env.backup
echo "Backup gemaakt in /opt/radiologger/.env.backup"

echo ""
echo "Stap 1: Radiologger bestanden bijwerken..."
cd /opt/radiologger || exit 1

# Controleer of dit een Git repository is
if [ -d ".git" ]; then
    echo "Git repository gevonden, bezig met updaten..."
    git fetch
    git pull
else
    echo "Geen Git repository gevonden, kopiëren van bestanden..."
    
    # Vergelijkbaar met de installatieoptie
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    
    if [ -f "$SCRIPT_DIR/main.py" ]; then
        echo "Kopiëren van bestanden uit de script directory..."
        # Maak eerst een backup van de hele directory
        timestamp=$(date +%Y%m%d-%H%M%S)
        cp -r /opt/radiologger /opt/radiologger.backup.$timestamp
        echo "Backup gemaakt in /opt/radiologger.backup.$timestamp"
        
        # Kopieer alle bestanden behalve .env naar de installatie map
        find "$SCRIPT_DIR" -type f -not -path "*/\.*" | grep -v "\.env$" | while read -r file; do
            rel_path="${file#$SCRIPT_DIR/}"
            parent_dir=$(dirname "/opt/radiologger/$rel_path")
            mkdir -p "$parent_dir"
            cp "$file" "/opt/radiologger/$rel_path"
        done
    else
        echo "Update bestanden niet gevonden. Geef de locatie van de nieuwe bestanden op."
        echo "Druk op Enter om de update te annuleren: "
        read -r custom_path
        
        if [ -z "$custom_path" ]; then
            echo "Update geannuleerd."
            exit 0
        elif [ -f "$custom_path/main.py" ]; then
            echo "Kopiëren van bestanden uit $custom_path..."
            timestamp=$(date +%Y%m%d-%H%M%S)
            cp -r /opt/radiologger /opt/radiologger.backup.$timestamp
            echo "Backup gemaakt in /opt/radiologger.backup.$timestamp"
            
            # Kopieer alle bestanden behalve .env
            find "$custom_path" -type f -not -path "*/\.*" | grep -v "\.env$" | while read -r file; do
                rel_path="${file#$custom_path/}"
                parent_dir=$(dirname "/opt/radiologger/$rel_path")
                mkdir -p "$parent_dir"
                cp "$file" "/opt/radiologger/$rel_path"
            done
        else
            echo "Geen geldige radiologger bestanden gevonden in $custom_path. Update geannuleerd."
            exit 1
        fi
    fi
fi

echo ""
echo "Stap 2: Dependencies updaten..."
/opt/radiologger/venv/bin/pip install --upgrade pip
/opt/radiologger/venv/bin/pip install -r export_requirements.txt

echo ""
echo "Stap 3: Database migraties uitvoeren..."
# Vraag of de gebruiker standaard stations wil
echo "Wil je de standaard radiostations uit de oude database gebruiken? (j/n): "
read -r use_default_stations
use_default_flag=""
if [[ "$use_default_stations" =~ ^[jJ]$ ]]; then
    use_default_flag="--use-default-stations"
    echo "Standaard stations uit de oude database worden gebruikt."
else
    echo "Bestaande stations worden behouden."
fi

sudo -u radiologger /opt/radiologger/venv/bin/flask db upgrade

# Alleen stations importeren als de gebruiker dat wil
if [[ -n "$use_default_flag" ]]; then
    # Reset stations als de gebruiker nieuwe stations wil importeren
    echo "Bestaande stations verwijderen voor import..."
    echo "Dit zal alle bestaande station configuraties verwijderen. Doorgaan? (j/n): "
    read -r confirm_reset
    if [[ "$confirm_reset" =~ ^[jJ]$ ]]; then
        # Gebruik psql om stations en gerelateerde records te verwijderen (nodig postgres wachtwoord)
        read -p "Voer het wachtwoord in voor de radiologger database gebruiker: " db_password
        # Eerst gerelateerde records in de recordings tabel verwijderen
        PGPASSWORD="$db_password" psql -h localhost -U radiologger -d radiologger -c "DELETE FROM recording WHERE station_id IN (SELECT id FROM station);"
        # Daarna scheduled_job records die naar stations verwijzen
        PGPASSWORD="$db_password" psql -h localhost -U radiologger -d radiologger -c "DELETE FROM scheduled_job WHERE station_id IN (SELECT id FROM station);"
        # Tenslotte de stations zelf verwijderen
        PGPASSWORD="$db_password" psql -h localhost -U radiologger -d radiologger -c "DELETE FROM station;"
        echo "Stations verwijderd. Nieuwe stations importeren..."
        sudo -u radiologger /opt/radiologger/venv/bin/python seed_data.py $use_default_flag
    else
        echo "Import geannuleerd, bestaande stations behouden."
    fi
fi

echo ""
echo "Stap 4: Rechten instellen en diensten herstarten..."
# Zorg ervoor dat bestandsrechten correct zijn ingesteld
chown -R radiologger:radiologger /opt/radiologger
chmod 600 /opt/radiologger/.env

# Maak logs directory als die niet bestaat
mkdir -p /var/log/radiologger
chown -R radiologger:radiologger /var/log/radiologger

# Maak recordings directory als die niet bestaat
mkdir -p /var/lib/radiologger/recordings
chown -R radiologger:radiologger /var/lib/radiologger

# Herstarten van diensten
systemctl restart radiologger
systemctl restart nginx

# Controleer status
echo "Controleren van radiologger service status..."
systemctl status radiologger --no-pager

echo ""
echo "====================================================================="
echo "Radiologger is succesvol bijgewerkt!"
echo "Je kunt de applicatie bekijken op https://logger.pilotradio.nl"
echo "====================================================================="