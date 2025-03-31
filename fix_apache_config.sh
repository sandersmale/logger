#!/bin/bash

# fix_apache_config.sh
# Script om Apache configuratie problemen op te lossen voor Radiologger
# Specifiek gericht op problemen met default pagina die nog steeds wordt getoond

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[INFO]${NC} Radiologger Apache configuratie herstel script"

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Stap 1: Deactiveer de default Apache site
echo -e "${YELLOW}[FIX]${NC} Deactiveren van default Apache site..."
a2dissite 000-default
echo -e "${GREEN}[OK]${NC} Default site gedeactiveerd"

# Stap 2: Maak de Radiologger configuratie
echo -e "${YELLOW}[FIX]${NC} Aanmaken van Radiologger Apache configuratie..."
cat > /etc/apache2/sites-available/radiologger.conf << 'EOL'
<VirtualHost *:80>
    ServerName _default_
    ServerAdmin webmaster@localhost
    
    # Proxy naar gunicorn op poort 5000
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:5000/
    ProxyPassReverse / http://127.0.0.1:5000/
    
    # Blokkeer de default html pagina
    <Directory /var/www/html>
        Require all denied
    </Directory>
    
    # Log configuratie
    ErrorLog ${APACHE_LOG_DIR}/radiologger-error.log
    CustomLog ${APACHE_LOG_DIR}/radiologger-access.log combined
</VirtualHost>
EOL
echo -e "${GREEN}[OK]${NC} Nieuwe configuratie aangemaakt"

# Stap 3: Activeer de Radiologger site
echo -e "${YELLOW}[FIX]${NC} Activeren van Radiologger site..."
a2ensite radiologger
echo -e "${GREEN}[OK]${NC} Radiologger site geactiveerd"

# Stap 4: Overschrijf de standaard index.html
echo -e "${YELLOW}[FIX]${NC} Overschrijven van standaard index.html..."
if [ -f /var/www/html/index.html ]; then
    mv /var/www/html/index.html /var/www/html/index.html.backup
fi

# Maak redirect pagina aan
cat > /var/www/html/index.html << 'EOL'
<!DOCTYPE html>
<html>
<head>
    <meta http-equiv="refresh" content="0; url=http://localhost:5000/">
    <title>Redirecting to Radiologger</title>
</head>
<body>
    <p>Redirecting to Radiologger...</p>
</body>
</html>
EOL
echo -e "${GREEN}[OK]${NC} Redirect pagina aangemaakt"

# Stap 5: Apache herladen
echo -e "${YELLOW}[FIX]${NC} Herladen van Apache configuratie..."
systemctl reload apache2 || systemctl restart apache2
echo -e "${GREEN}[OK]${NC} Apache configuratie herladen"

# Stap 6: Controleer of radiologger service draait
echo -e "${YELLOW}[CHECK]${NC} Controleren of Radiologger service draait..."
if ! systemctl is-active --quiet radiologger; then
    echo -e "${RED}[ERROR]${NC} Radiologger service draait niet. Starten..."
    systemctl start radiologger
    sleep 3
    if systemctl is-active --quiet radiologger; then
        echo -e "${GREEN}[OK]${NC} Radiologger service gestart"
    else
        echo -e "${RED}[ERROR]${NC} Kon Radiologger service niet starten!"
        echo -e "${YELLOW}[INFO]${NC} Controleer service logs met: sudo journalctl -u radiologger -n 50"
    fi
else
    echo -e "${GREEN}[OK]${NC} Radiologger service draait al"
fi

echo -e "\n${GREEN}[DONE]${NC} Apache configuratie herstel voltooid!"
echo -e "${YELLOW}[INFO]${NC} Probeer nu je browser te vernieuwen (druk op Ctrl+F5)"
echo -e "${YELLOW}[INFO]${NC} Als je nog steeds de default pagina ziet, probeer:"
echo -e "  1. Je browser cache leegmaken"
echo -e "  2. Een volledige Apache herstart: sudo systemctl restart apache2"
echo -e "  3. Een andere browser of incognito modus gebruiken"
echo -e "  4. Toegang via http://server-ip:5000/ om te controleren of de app zelf draait"

echo -e "\n${YELLOW}[INFO]${NC} Test verbinding:"
echo -e "${YELLOW}[INFO]${NC} Directe verbinding met app op poort 5000:"
curl -s http://localhost:5000/ | grep -o '<title>.*</title>' || echo "Kon geen verbinding maken met app"

echo -e "${YELLOW}[INFO]${NC} Verbinding via Apache:"
curl -s http://localhost/ | grep -o '<title>.*</title>' || echo "Kon geen verbinding maken via Apache"

exit 0