#!/bin/bash

# diagnose_apache.sh
# Apache diagnostisch script voor Radiologger
# Dit script lost problemen op met Apache configuratie en sites

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[INFO]${NC} Apache diagnose voor Radiologger gestart"

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Controleer of Apache draait
echo -e "${YELLOW}[CHECK]${NC} Controleren of Apache draait..."
if systemctl is-active --quiet apache2; then
    echo -e "${GREEN}[OK]${NC} Apache draait actief"
else
    echo -e "${RED}[ERROR]${NC} Apache draait NIET. Starten..."
    systemctl start apache2
fi

# Controleer nodige modules
echo -e "${YELLOW}[CHECK]${NC} Controleren of nodige Apache modules geladen zijn..."
MODULES=("proxy" "proxy_http" "wsgi" "ssl" "rewrite" "headers")
RESTART_NEEDED=false

for mod in "${MODULES[@]}"; do
    if ! apache2ctl -M 2>/dev/null | grep -q "$mod"; then
        echo -e "${RED}[ERROR]${NC} Module $mod niet geladen. Activeren..."
        a2enmod $mod
        RESTART_NEEDED=true
    else
        echo -e "${GREEN}[OK]${NC} Module $mod is geladen"
    fi
done

# Controleer sites-enabled
echo -e "${YELLOW}[CHECK]${NC} Controleren welke sites geactiveerd zijn..."
ls -la /etc/apache2/sites-enabled/

# Schakel default site uit als deze nog actief is
if [ -L /etc/apache2/sites-enabled/000-default.conf ]; then
    echo -e "${RED}[ERROR]${NC} Default site nog actief. Uitschakelen..."
    a2dissite 000-default
    RESTART_NEEDED=true
fi

# Controleer radiologger configuratie
echo -e "${YELLOW}[CHECK]${NC} Controleren of Radiologger Apache configuratie correct is..."

# Zoek welk configuratiebestand wordt gebruikt
RADIOLOGGER_CONF=""
if [ -f /etc/apache2/sites-available/radiologger.conf ]; then
    RADIOLOGGER_CONF="/etc/apache2/sites-available/radiologger.conf"
elif [ -f /etc/apache2/sites-available/radiologger_apache.conf ]; then
    RADIOLOGGER_CONF="/etc/apache2/sites-available/radiologger_apache.conf"
fi

if [ -z "$RADIOLOGGER_CONF" ]; then
    echo -e "${RED}[ERROR]${NC} Geen Radiologger Apache configuratie gevonden. Aanmaken..."
    
    # Maak nieuwe configuratie
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
    RADIOLOGGER_CONF="/etc/apache2/sites-available/radiologger.conf"
    echo -e "${GREEN}[OK]${NC} Nieuwe configuratie aangemaakt: $RADIOLOGGER_CONF"
    
    # Activeer de site
    a2ensite radiologger
    RESTART_NEEDED=true
else
    echo -e "${GREEN}[OK]${NC} Radiologger Apache configuratie gevonden: $RADIOLOGGER_CONF"
    
    # Controleer of de configuratie is geactiveerd
    CONF_FILENAME=$(basename "$RADIOLOGGER_CONF")
    if ! [ -L "/etc/apache2/sites-enabled/$CONF_FILENAME" ]; then
        echo -e "${RED}[ERROR]${NC} Radiologger configuratie is NIET geactiveerd. Activeren..."
        a2ensite "$CONF_FILENAME"
        RESTART_NEEDED=true
    else
        echo -e "${GREEN}[OK]${NC} Radiologger configuratie is geactiveerd"
    fi
    
    # Controleer de inhoud van de configuratie
    echo -e "${YELLOW}[CHECK]${NC} Controleren inhoud van configuratie..."
    if ! grep -q "ProxyPass / http://127.0.0.1:5000/" "$RADIOLOGGER_CONF"; then
        echo -e "${RED}[ERROR]${NC} Proxy configuratie ontbreekt of is incorrect. Herstellen..."
        
        # Backup maken van oude configuratie
        cp "$RADIOLOGGER_CONF" "${RADIOLOGGER_CONF}.backup"
        
        # Vervang de configuratie
        cat > "$RADIOLOGGER_CONF" << 'EOL'
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
        echo -e "${GREEN}[OK]${NC} Configuratie bijgewerkt"
        RESTART_NEEDED=true
    else
        echo -e "${GREEN}[OK]${NC} Configuratie bevat correcte proxy instellingen"
    fi
fi

# Controleer of de default index.html de doorverwijzing blokkeert
echo -e "${YELLOW}[CHECK]${NC} Controleren of de default Apache welkomstpagina aanwezig is..."
if [ -f /var/www/html/index.html ]; then
    echo -e "${RED}[ERROR]${NC} Default Apache welkomstpagina gevonden. Hernoemen..."
    mv /var/www/html/index.html /var/www/html/index.html.backup
    
    # Maak een redirect pagina
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
fi

# Controleer of radiologger service draait
echo -e "${YELLOW}[CHECK]${NC} Controleren of Radiologger service draait..."
if ! systemctl is-active --quiet radiologger; then
    echo -e "${RED}[ERROR]${NC} Radiologger service draait NIET. Starten..."
    systemctl start radiologger
    sleep 3
    
    if ! systemctl is-active --quiet radiologger; then
        echo -e "${RED}[ERROR]${NC} Kon Radiologger service niet starten!"
        echo -e "${YELLOW}[INFO]${NC} Log output:"
        journalctl -u radiologger --no-pager -n 20
    else
        echo -e "${GREEN}[OK]${NC} Radiologger service gestart"
    fi
else
    echo -e "${GREEN}[OK]${NC} Radiologger service draait"
fi

# Controleer of poort 5000 open is
echo -e "${YELLOW}[CHECK]${NC} Controleren of poort 5000 open is..."
if netstat -tuln | grep -q ":5000"; then
    echo -e "${GREEN}[OK]${NC} Poort 5000 is open en actief"
else
    echo -e "${RED}[ERROR]${NC} Poort 5000 is NIET open!"
    echo -e "${YELLOW}[INFO]${NC} Dit kan betekenen dat Gunicorn niet goed draait."
    echo -e "${YELLOW}[INFO]${NC} Controleer de Radiologger service logs."
fi

# Controleer verbinding met de applicatie
echo -e "${YELLOW}[CHECK]${NC} Controleren verbinding met de applicatie..."
if curl -s http://localhost:5000/ | grep -q "login"; then
    echo -e "${GREEN}[OK]${NC} Verbinding met de applicatie succesvol"
else
    echo -e "${RED}[ERROR]${NC} Kon geen verbinding maken met de applicatie!"
fi

# Restart Apache indien nodig
if [ "$RESTART_NEEDED" = true ]; then
    echo -e "${YELLOW}[FIX]${NC} Herstarten van Apache na configuratiewijzigingen..."
    systemctl reload apache2 || systemctl restart apache2
    echo -e "${GREEN}[OK]${NC} Apache herstart/herladen voltooid"
fi

echo -e "\n${GREEN}[DONE]${NC} Apache diagnose en herstel voltooid!"
echo -e "${YELLOW}[INFO]${NC} Als je nog steeds de default Apache pagina ziet, probeer:"
echo -e "  1. Je browser cache leegmaken"
echo -e "  2. Een volledige Apache herstart: sudo systemctl restart apache2"
echo -e "  3. Controleer met curl -s http://localhost/ of je de juiste inhoud krijgt"

exit 0