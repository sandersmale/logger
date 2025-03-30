#!/bin/bash
# Fix permissions script voor Radiologger
# Dit script corrigeert de meest voorkomende permissie problemen die leiden tot 502 errors

echo "Radiologger Permissie Fix Script"
echo "=============================="
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Voer permissie-fixes uit
echo "Permissies repareren voor applicatie mappen..."
mkdir -p /opt/radiologger
mkdir -p /var/log/radiologger
mkdir -p /var/lib/radiologger/recordings

# Zorg ervoor dat de radiologger gebruiker bestaat
if ! id -u radiologger &>/dev/null; then
    echo "Radiologger gebruiker aanmaken..."
    useradd -m radiologger -s /bin/bash
fi

# Fix eigenaarschap
echo "Eigenaarschap instellen..."
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger

# Fix permissies
echo "Lees- en schrijfrechten instellen..."
chmod -R 755 /opt/radiologger
chmod -R 755 /var/log/radiologger
chmod -R 755 /var/lib/radiologger

# Controleer en repareer SELinux contexten indien van toepassing
if command -v sestatus &>/dev/null && sestatus | grep -q "enabled"; then
    echo "SELinux contexten repareren..."
    if command -v restorecon &>/dev/null; then
        restorecon -Rv /opt/radiologger
        restorecon -Rv /var/log/radiologger
        restorecon -Rv /var/lib/radiologger
    fi
fi

# Controleer socket permissies
echo "Socket permissies controleren..."
if netstat -tuln | grep -q ":5000"; then
    echo "Poort 5000 in gebruik, processen opnieuw starten..."
    systemctl restart radiologger
    systemctl restart nginx
fi

# Log instellingen checken
echo "Log schrijfrechten controleren..."
touch /var/log/radiologger/test.log
sudo -u radiologger touch /var/log/radiologger/test_user.log
if [ $? -ne 0 ]; then
    echo "⚠️ Radiologger gebruiker kan niet schrijven naar logs!"
    echo "Repareren..."
    chmod 775 /var/log/radiologger
else
    echo "✅ Log schrijfrechten OK"
    rm -f /var/log/radiologger/test.log
    rm -f /var/log/radiologger/test_user.log
fi

# Systemd service herstarten
echo "Radiologger service herstarten..."
systemctl daemon-reload
systemctl restart radiologger
systemctl status radiologger

# Nginx herstarten
echo "Nginx herstarten..."
systemctl restart nginx
systemctl status nginx

echo ""
echo "✅ Permissie fixes voltooid!"
echo "Als je nog steeds 502 Bad Gateway ziet, controleer de logs met:"
echo "sudo journalctl -u radiologger -n 50"
echo "en"
echo "sudo tail -n 50 /var/log/nginx/radiologger_error.log"