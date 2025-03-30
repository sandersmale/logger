#!/bin/bash
# Radiologger uninstallatiescript voor Ubuntu 24.04
# Dit script maakt alle wijzigingen ongedaan die door install.sh zijn aangebracht
#
# Gebruik: sudo bash uninstall.sh

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   if [[ "$1" != "--replit-test" ]]; then
      echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
      exit 1
   else
      echo "Replit test modus - root check wordt overgeslagen"
   fi
fi

echo "Radiologger uninstallatiescript voor Ubuntu 24.04"
echo "=================================================="
echo ""
echo "Dit script zal alle wijzigingen ongedaan maken die zijn aangebracht door het installatiescript:"
echo "1. Systemd service stoppen en verwijderen"
echo "2. Nginx configuratie verwijderen"
echo "3. PostgreSQL database verwijderen"
echo "4. Radiologger gebruiker verwijderen"
echo "5. Alle gemaakte mappen en bestanden verwijderen"
echo "6. Geïnstalleerde pakketten verwijderen"
echo "7. Zichzelf verwijderen (dit script)"
echo ""
# Check for non-interactive mode (flag --force of -f)
if [[ "$1" == "--force" || "$1" == "-f" || "$2" == "--force" || "$2" == "-f" ]]; then
    echo "Automatische uninstallatie wordt uitgevoerd zonder bevestiging..."
    confirm="j"
else
    echo "WAARSCHUWING: Dit proces kan niet ongedaan worden gemaakt!"
    read -p "Weet je zeker dat je wilt doorgaan? (j/n): " confirm
    if [[ ! "$confirm" =~ ^[jJ]$ ]]; then
        echo "Uninstallatie geannuleerd."
        exit 0
    fi
fi

# Stop en verwijder de systemd service
echo "Systemd service stoppen en verwijderen..."
systemctl stop radiologger 2>/dev/null || true
systemctl disable radiologger 2>/dev/null || true
rm -f /etc/systemd/system/radiologger.service
systemctl daemon-reload
echo "✅ Systemd service gestopt en verwijderd"

# Verwijder de Nginx configuratie
echo "Nginx configuratie verwijderen..."
rm -f /etc/nginx/sites-enabled/radiologger
rm -f /etc/nginx/sites-available/radiologger
# Reload Nginx als het actief is
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
fi
echo "✅ Nginx configuratie verwijderd"

# Verwijder de PostgreSQL database en gebruiker
echo "PostgreSQL database en gebruiker verwijderen..."
if command -v psql &>/dev/null; then
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS radiologger;" || true
    sudo -u postgres psql -c "DROP USER IF EXISTS radiologger;" || true
    echo "✅ Database en gebruiker verwijderd"
else
    echo "⚠️ PostgreSQL commando niet gevonden, database handmatig verwijderen"
fi

# Verwijder de radiologger gebruiker
echo "Radiologger gebruiker verwijderen..."
pkill -u radiologger 2>/dev/null || true  # Kill processen die draaien als radiologger
userdel -r radiologger 2>/dev/null || true
echo "✅ Radiologger gebruiker verwijderd"

# Verwijder alle mappen en bestanden
echo "Mappen en bestanden verwijderen..."
rm -rf /opt/radiologger
rm -rf /var/log/radiologger
rm -rf /var/lib/radiologger
echo "✅ Alle mappen en bestanden verwijderd"

# Verwijder eventuele certificaten van Let's Encrypt
echo "Let's Encrypt certificaten controleren..."
if [[ -d /etc/letsencrypt/live/logger.pilotradio.nl ]]; then
    echo "Let's Encrypt certificaten gevonden, niet automatisch verwijderd voor veiligheid"
    echo "Gebruik 'certbot delete' om ze handmatig te verwijderen indien gewenst"
fi

# Probeer crontab entries te verwijderen als ze bestaan
echo "Controleren op crontab entries..."
if crontab -l 2>/dev/null | grep -q radiologger; then
    echo "Radiologger crontab entries gevonden, verwijderen..."
    (crontab -l 2>/dev/null | grep -v radiologger) | crontab -
    echo "✅ Crontab entries verwijderd"
fi

# Verwijder de geïnstalleerde pakketten
echo "Geïnstalleerde pakketten verwijderen..."
# Lijst van pakketten die mogelijk geïnstalleerd zijn voor radiologger
INSTALLED_PACKAGES=""

# Controleer Python-gerelateerde pakketten
for pkg in python3 python3-pip python3-venv python3-dev; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES $pkg"
    fi
done

# Controleer PostgreSQL
for pkg in postgresql postgresql-contrib postgresql-client; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES $pkg"
    fi
done

# Controleer webserver en ssl gerelateerde pakketten
for pkg in nginx certbot python3-certbot-nginx; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES $pkg"
    fi
done

# Controleer multimedia en ontwikkelingstools
for pkg in ffmpeg build-essential libpq-dev; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES $pkg"
    fi
done

# Controleer extra tools
for pkg in htop curl vim rsync; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES $pkg"
    fi
done

# Alleen verwijderen als de gebruiker dit expliciet wil
if [[ -n "$INSTALLED_PACKAGES" ]]; then
    echo "De volgende pakketten zijn geïnstalleerd en kunnen verwijderd worden:"
    echo "$INSTALLED_PACKAGES"
    
    if [[ "$confirm" == "j" && "$1" == "--purge-all" ]]; then
        echo "Alle pakketten verwijderen..."
        apt-get -y purge $INSTALLED_PACKAGES
        apt-get -y autoremove --purge
        echo "✅ Alle geïnstalleerde pakketten zijn verwijderd"
    else
        echo "Om alle pakketten te verwijderen, voer het script uit met: sudo bash uninstall.sh --purge-all"
        echo "⚠️ Pakketten niet verwijderd: voeg --purge-all toe om ze te verwijderen"
    fi
else
    echo "Geen specifieke pakketten gevonden die verwijderd moeten worden"
fi

echo ""
echo "✅ Radiologger is volledig verwijderd van het systeem!"
echo "Indien gewenst kun je nu veilig opnieuw installeren."

# Verwijder het script zelf als laatste
SCRIPT_PATH="$(readlink -f "$0")"
echo "Dit script zal zichzelf nu verwijderen..."
# Maak een tijdelijk script dat het eigenlijke script verwijdert
TMP_SCRIPT=$(mktemp)
cat > "$TMP_SCRIPT" << EOL
#!/bin/bash
# Wacht even zodat het hoofdscript kan afsluiten
sleep 1
# Verwijder het hoofdscript
rm -f "$SCRIPT_PATH"
# Verwijder dit tijdelijke script
rm -f "\$0"
EOL
chmod +x "$TMP_SCRIPT"
# Voer het tijdelijke script uit in de achtergrond
"$TMP_SCRIPT" &