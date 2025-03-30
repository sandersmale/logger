#!/bin/bash
# Diagnose script voor 502 Bad Gateway in Radiologger
# Dit script controleert de status van de service, logs, en configuraties

echo "Radiologger Diagnose Script"
echo "==========================="
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Controleer systemd service status
echo "Controleren van Radiologger service status..."
systemctl status radiologger
SERVICE_RUNNING=$?

if [ $SERVICE_RUNNING -ne 0 ]; then
    echo "⚠️ De Radiologger service draait niet!"
    echo "Start poging..."
    systemctl start radiologger
    sleep 3
    systemctl status radiologger
    SERVICE_RUNNING=$?
    
    if [ $SERVICE_RUNNING -ne 0 ]; then
        echo "❌ De service kon niet worden gestart!"
        echo "Servicelog bekijken voor meer details:"
        journalctl -u radiologger --no-pager -n 50
    else
        echo "✅ De service is nu gestart!"
    fi
else
    echo "✅ De Radiologger service draait!"
fi

# Controleer poortbinding
echo ""
echo "Controleren op poortbinding port 5000..."
PORT_OPEN=$(ss -tuln | grep :5000)

if [ -z "$PORT_OPEN" ]; then
    echo "❌ Geen proces luistert op poort 5000!"
else
    echo "✅ Er is een proces dat luistert op poort 5000: $PORT_OPEN"
fi

# Controleer nginx configuratie
echo ""
echo "Controleren van Nginx configuratie..."
nginx -t

# Controleren of de proxy werkt via curl
echo ""
echo "Testen van lokale verbinding naar applicatie..."
curl -s -I http://127.0.0.1:5000 || echo "❌ Kan geen verbinding maken met de applicatie!"

# Controleer permissies
echo ""
echo "Controleren van permissies voor belangrijke mappen..."
ls -ld /opt/radiologger
ls -ld /var/log/radiologger

# Controleer Python omgeving
echo ""
echo "Controleren Python omgeving..."
if [ -f /opt/radiologger/venv/bin/python ]; then
    echo "✅ Python virtual environment gevonden"
    /opt/radiologger/venv/bin/python --version
    echo "Geïnstalleerde Python pakketten:"
    /opt/radiologger/venv/bin/pip freeze | grep -E "(flask|gunicorn|sqlalchemy)"
else
    echo "❌ Python virtual environment niet gevonden!"
fi

# Controleer applicatie logs
echo ""
echo "Checken applicatie logs..."
if [ -f /var/log/radiologger/error.log ]; then
    echo "Laatste 10 regels van error.log:"
    tail -n 10 /var/log/radiologger/error.log
else
    echo "❌ Applicatie error log niet gevonden!"
fi

# Nginx error logs
echo ""
echo "Checken Nginx logs..."
if [ -f /var/log/nginx/radiologger_error.log ]; then
    echo "Laatste 10 regels van nginx error log:"
    tail -n 10 /var/log/nginx/radiologger_error.log
else
    echo "❌ Nginx error log niet gevonden!"
fi

# Fix-acties
echo ""
echo "Mogelijke oplossingen:"
echo "1. Herstarten van de service:"
echo "   sudo systemctl restart radiologger"
echo ""
echo "2. Herstarten van Nginx:"
echo "   sudo systemctl restart nginx"
echo ""
echo "3. Controleer .env bestand:"
echo "   sudo nano /opt/radiologger/.env"
echo ""
echo "4. Fix permissies:"
echo "   sudo chown -R radiologger:radiologger /opt/radiologger"
echo "   sudo chown -R radiologger:radiologger /var/log/radiologger"
echo ""
echo "5. Handmatig starten om details te zien:"
echo "   sudo -u radiologger /opt/radiologger/venv/bin/gunicorn --chdir /opt/radiologger --bind 0.0.0.0:5000 main:app"
echo ""
echo "6. Als niets anders werkt, overweeg het volgende:"
echo "   sudo bash /opt/radiologger/find_env_issues.sh"
echo ""

# Automatische fix-acties
echo "Wil je automatisch een aantal standaard fixes proberen? (j/n)"
read -r AUTO_FIX

if [[ "$AUTO_FIX" =~ ^[jJ]$ ]]; then
    echo "Automatische fixes uitvoeren..."
    
    # Fix permissies
    echo "Permissies fixen..."
    chown -R radiologger:radiologger /opt/radiologger
    chown -R radiologger:radiologger /var/log/radiologger
    chmod 755 /opt/radiologger
    chmod 755 /var/log/radiologger
    
    # Controleer socket
    echo "Poort 5000 resetten..."
    fuser -k 5000/tcp 2>/dev/null || true
    
    # Herstarten van services
    echo "Services herstarten..."
    systemctl restart radiologger
    systemctl restart nginx
    
    echo "Wachten op services om op te starten..."
    sleep 5
    
    # Toon resultaten
    echo "Status na fixes:"
    systemctl status radiologger --no-pager -n 10
    curl -s -I http://127.0.0.1:5000 || echo "❌ Kan nog steeds geen verbinding maken met de applicatie!"
fi

echo ""
echo "Diagnose voltooid! Als de problemen blijven bestaan, gebruik de getoonde informatie"
echo "om te begrijpen wat er mis is en volg de voorgestelde oplossingen."