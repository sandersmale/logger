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
echo "Stap 1: Git repository updaten..."
cd /opt/radiologger || exit 1
git fetch
git pull

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
echo "Stap 4: Diensten herstarten..."
systemctl restart radiologger
systemctl restart nginx

echo ""
echo "====================================================================="
echo "Radiologger is succesvol bijgewerkt!"
echo "Je kunt de applicatie bekijken op https://logger.pilotradio.nl"
echo "====================================================================="