#!/bin/bash
# Radiologger fix permissions script
# Dit script herstelt alle permissies voor de radiologger applicatie

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

echo "Radiologger Permissie Fix Script"
echo "=============================="
echo ""

# Fix permissies voor hoofdmappen
echo "Permissies fixen voor hoofdmappen..."
chown -R radiologger:radiologger /opt/radiologger
chmod -R 755 /opt/radiologger
chmod 600 /opt/radiologger/.env 2>/dev/null || echo "Waarschuwing: .env bestand niet gevonden"

# Fix permissies voor log mappen
echo "Permissies fixen voor log mappen..."
if [ -d /var/log/radiologger ]; then
    chown -R radiologger:radiologger /var/log/radiologger
    chmod -R 755 /var/log/radiologger
else
    echo "Waarschuwing: Log map niet gevonden, aanmaken..."
    mkdir -p /var/log/radiologger
    chown -R radiologger:radiologger /var/log/radiologger
    chmod -R 755 /var/log/radiologger
fi

# Fix permissies voor opname mappen
echo "Permissies fixen voor opname mappen..."
if [ -d /var/lib/radiologger/recordings ]; then
    chown -R radiologger:radiologger /var/lib/radiologger/recordings
    chmod -R 755 /var/lib/radiologger/recordings
else
    echo "Waarschuwing: Opname map niet gevonden, aanmaken..."
    mkdir -p /var/lib/radiologger/recordings
    chown -R radiologger:radiologger /var/lib/radiologger/recordings
    chmod -R 755 /var/lib/radiologger/recordings
fi

# Fix HOME directory in systemd service
echo "Controleren en fixen van HOME directory in systemd service..."
if [ -f /etc/systemd/system/radiologger.service ]; then
    if ! grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
        echo "HOME directory toevoegen aan service..."
        sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✅ HOME directory toegevoegd aan service, systemd herladen"
    else
        echo "✅ HOME directory al ingesteld in service"
    fi
else
    echo "❌ Systemd service bestand niet gevonden!"
fi

# Controleer EnvironmentFile in systemd service
echo "Controleren en fixen van EnvironmentFile in systemd service..."
if [ -f /etc/systemd/system/radiologger.service ]; then
    if ! grep -q "EnvironmentFile=/opt/radiologger/.env" /etc/systemd/system/radiologger.service; then
        echo "EnvironmentFile toevoegen aan service..."
        sed -i '/\[Service\]/a EnvironmentFile=/opt/radiologger/.env' /etc/systemd/system/radiologger.service
        systemctl daemon-reload
        echo "✅ EnvironmentFile toegevoegd aan service, systemd herladen"
    else
        echo "✅ EnvironmentFile al ingesteld in service"
    fi
fi

# Controleer of main.py bestaat
echo "Controleren of main.py bestaat..."
if [ ! -f /opt/radiologger/main.py ]; then
    echo "❌ main.py bestand niet gevonden, aanmaken..."
    cat > /opt/radiologger/main.py << 'EOL'
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
    chmod 755 /opt/radiologger/main.py
    chown radiologger:radiologger /opt/radiologger/main.py
    echo "✅ main.py succesvol aangemaakt"
else
    echo "✅ main.py bestand gevonden"
fi

# Controleer of venv bestaat en permissies
echo "Controleren van Python virtual environment..."
if [ -d /opt/radiologger/venv ]; then
    echo "✅ Python virtual environment gevonden, permissies fixen..."
    chown -R radiologger:radiologger /opt/radiologger/venv
    chmod -R 755 /opt/radiologger/venv
else
    echo "❌ Python virtual environment niet gevonden!"
fi

# Herstart services
echo ""
echo "Herstarten van services..."
echo "Radiologger service herstarten..."
systemctl restart radiologger
echo "Apache2 herstarten..."
systemctl restart apache2

# Toon status
echo ""
echo "Service status na fix:"
systemctl status radiologger --no-pager -n 5

echo ""
echo "✅ Radiologger permissies succesvol gerepareerd!"
echo "Controleer de webinterface door te navigeren naar je domein"