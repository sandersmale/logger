#!/bin/bash
# Fix permissies script voor de Radiologger applicatie
# Dit script repareert alle bestandsrechten en eigenaarschap

# Controleren of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

echo "Radiologger Permissions Fix Script"
echo "=================================="
echo ""

# Fix eigenaarschap
echo "Repareren van eigenaarschap van bestanden en mappen..."
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger

# Fix bestandsrechten
echo "Repareren van bestandsrechten..."
chmod 755 /opt/radiologger
chmod 755 /var/log/radiologger
chmod 755 /var/lib/radiologger
chmod 755 /var/lib/radiologger/recordings

# Fix .env bestand
echo "Repareren van .env bestandsrechten..."
if [ -f /opt/radiologger/.env ]; then
  chmod 640 /opt/radiologger/.env
  chown radiologger:radiologger /opt/radiologger/.env
  echo "✅ .env bestand rechten gecorrigeerd"
else
  echo "⚠️ .env bestand niet gevonden!"
fi

# Fix Python omgeving
echo "Repareren van Python virtual environment rechten..."
if [ -d /opt/radiologger/venv ]; then
  chown -R radiologger:radiologger /opt/radiologger/venv
  chmod -R 755 /opt/radiologger/venv
  echo "✅ Python virtual environment rechten gecorrigeerd"
else
  echo "⚠️ Python virtual environment niet gevonden!"
fi

# Fix uitvoerbare Python scripts
echo "Uitvoerbare bestanden controleren..."
for script in /opt/radiologger/*.py; do
  if [ -f "$script" ]; then
    chmod 755 "$script"
  fi
done
echo "✅ Python scripts executable gemaakt"

# Fix nginx configuratie (indien aanwezig)
if [ -f /etc/nginx/sites-available/radiologger ]; then
  chmod 644 /etc/nginx/sites-available/radiologger
  echo "✅ Nginx configuratie rechten gecorrigeerd"
fi

# Fix HOME directory voor de service
echo "HOME directory repareren in de service configuratie..."
if [ -f /etc/systemd/system/radiologger.service ]; then
  if ! grep -q "Environment=\"HOME=/opt/radiologger\"" /etc/systemd/system/radiologger.service; then
    # Voeg HOME toe aan de radiologger.service als het ontbreekt
    sed -i '/\[Service\]/a Environment="HOME=/opt/radiologger"' /etc/systemd/system/radiologger.service
    echo "✅ HOME directory in systemd service toegevoegd"
    
    # Herlaad systemd en restart de service
    systemctl daemon-reload
    systemctl restart radiologger
  else
    echo "✅ HOME directory is al correct ingesteld in de service"
  fi
else
  echo "⚠️ Radiologger service bestand niet gevonden!"
fi

# Check main.py bestaat
echo "Controleren of main.py bestaat..."
if [ -f /opt/radiologger/main.py ]; then
  echo "✅ main.py bestaat"
  chmod 755 /opt/radiologger/main.py
  chown radiologger:radiologger /opt/radiologger/main.py
  echo "✅ Rechten voor main.py gecorrigeerd"
else
  echo "❌ main.py bestaat niet! Dit is nodig voor Gunicorn."
  # Maak main.py aan als het niet bestaat
  echo "📝 main.py aanmaken..."
  cat > /opt/radiologger/main.py << 'EOL'
from app import app

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
EOL
  chmod 755 /opt/radiologger/main.py
  chown radiologger:radiologger /opt/radiologger/main.py
  echo "✅ main.py aangemaakt en geconfigureerd"
fi

# Verificatie
echo ""
echo "Verificatie van rechten:"
ls -ld /opt/radiologger
ls -ld /var/log/radiologger
ls -ld /var/lib/radiologger
ls -ld /var/lib/radiologger/recordings
if [ -f /opt/radiologger/.env ]; then
  ls -l /opt/radiologger/.env
fi
ls -l /opt/radiologger/main.py

echo ""
echo "✅ Alle rechten zijn gerepareerd!"
echo "Herstart de Radiologger service met: sudo systemctl restart radiologger"
echo "Herstart Nginx met: sudo systemctl restart nginx"