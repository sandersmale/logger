#!/bin/bash
# Nginx troubleshoot script voor 502 Bad Gateway
# Dit script controleert en repareert Nginx instellingen specifiek voor 502 fouten

echo "Nginx 502 Troubleshoot Script"
echo "============================"
echo ""

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Controleer Nginx configuratie
echo "Nginx configuratie controleren..."
nginx -t
if [ $? -ne 0 ]; then
    echo "❌ Nginx configuratie bevat fouten!"
    exit 1
fi

# Check if nginx is running
echo "Nginx service status controleren..."
systemctl status nginx
NGINX_RUNNING=$?

if [ $NGINX_RUNNING -ne 0 ]; then
    echo "⚠️ Nginx service draait niet! Starten..."
    systemctl start nginx
    sleep 2
    systemctl status nginx
    if [ $? -ne 0 ]; then
        echo "❌ Kon Nginx niet starten!"
        exit 1
    fi
fi

# Check upstream service (Radiologger app)
echo "Controleren of de applicatie draait op poort 5000..."
APP_RESPONSE=$(curl -s -I -m 5 http://127.0.0.1:5000 || echo "Failed")

if echo "$APP_RESPONSE" | grep -q "Failed"; then
    echo "❌ De applicatie reageert niet op poort 5000!"
    echo "Controleren of de radiologger service draait..."
    
    systemctl status radiologger
    if [ $? -ne 0 ]; then
        echo "⚠️ Radiologger service draait niet! Starten..."
        systemctl start radiologger
        sleep 5
        APP_RESPONSE=$(curl -s -I -m 5 http://127.0.0.1:5000 || echo "Failed")
        
        if echo "$APP_RESPONSE" | grep -q "Failed"; then
            echo "❌ De applicatie reageert nog steeds niet na starten van de service!"
            echo "Logs bekijken..."
            journalctl -u radiologger --no-pager -n 20
        else
            echo "✅ Applicatie reageert nu!"
        fi
    fi
else
    echo "✅ Applicatie reageert op poort 5000!"
    echo "$APP_RESPONSE"
fi

# Controleer Nginx proxy configuratie
echo "Controleren of proxy configuratie correct is..."
if grep -q "proxy_pass http://127.0.0.1:5000" /etc/nginx/sites-enabled/radiologger; then
    echo "✅ Proxy configuratie lijkt correct!"
else
    echo "❌ Proxy configuratie onjuist of ontbreekt!"
    
    # Check of het bestand bestaat
    if [ ! -f /etc/nginx/sites-enabled/radiologger ]; then
        echo "⚠️ Nginx configuratie ontbreekt in sites-enabled!"
        
        if [ -f /etc/nginx/sites-available/radiologger ]; then
            echo "Configuratie gevonden in sites-available, symlink maken..."
            ln -sf /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/radiologger
            systemctl reload nginx
        else
            echo "❌ Configuratie ontbreekt volledig!"
            
            # Configuratie herstellen
            if [ -f /opt/radiologger/radiologger_nginx.conf ]; then
                echo "Configuratie in applicatiemap gevonden, kopiëren..."
                cp /opt/radiologger/radiologger_nginx.conf /etc/nginx/sites-available/radiologger
                ln -sf /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/radiologger
                systemctl reload nginx
            fi
        fi
    fi
fi

# Controleer SSL configuratie indien HTTPS gebruikt wordt
echo "SSL configuratie controleren..."
if grep -q "ssl_certificate" /etc/nginx/sites-enabled/radiologger; then
    echo "SSL configuratie gevonden, certificaten controleren..."
    SSL_CERT=$(grep -oP "ssl_certificate \K[^;]+" /etc/nginx/sites-enabled/radiologger)
    
    if [ -f "$SSL_CERT" ]; then
        echo "✅ SSL certificaat bestaat!"
        
        # Controleer verloopdatum
        EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_CERT" | cut -d= -f 2)
        echo "Certificaat verloopt op: $EXPIRY"
    else
        echo "❌ SSL certificaat niet gevonden op pad: $SSL_CERT"
        echo "Certificaat opnieuw aanvragen met Let's Encrypt?"
        read -p "(j/n): " RENEW_CERT
        
        if [[ "$RENEW_CERT" =~ ^[jJ]$ ]]; then
            echo "Certificaat vernieuwen met Certbot..."
            certbot --nginx -d logger.pilotradio.nl
        fi
    fi
fi

# Controleer loggings en bestaande logs
echo "Nginx logs controleren..."
if [ -f /var/log/nginx/radiologger_error.log ]; then
    echo "Laatste 10 regels uit error log:"
    tail -n 10 /var/log/nginx/radiologger_error.log
else
    echo "⚠️ Nginx error log niet gevonden!"
fi

# Probeer Nginx en de applicatie te herstarten
echo "Services herstarten om te kijken of dit het probleem oplost..."
systemctl restart radiologger
systemctl restart nginx
sleep 5

# Finale check
echo "Controle na herstarten..."
APP_RESPONSE=$(curl -s -I -m 5 http://127.0.0.1:5000 || echo "Failed")
if echo "$APP_RESPONSE" | grep -q "Failed"; then
    echo "❌ De applicatie reageert nog steeds niet op poort 5000!"
    echo "Dit kan wijzen op een dieper probleem met de applicatie zelf."
    echo "Controleer met 'sudo journalctl -u radiologger' voor meer details."
else
    echo "✅ Applicatie reageert op poort 5000!"
    echo "$APP_RESPONSE"
    echo "Nginx zou nu de applicatie correct moeten kunnen bereiken."
    echo "Probeer logger.pilotradio.nl opnieuw te bezoeken."
fi

echo ""
echo "Troubleshooting voltooid. Als het probleem blijft bestaan,"
echo "overweeg om de volledige logs te bekijken:"
echo "sudo journalctl -u radiologger -n 200"
echo "sudo journalctl -u nginx -n 50"
echo "sudo cat /var/log/nginx/radiologger_error.log"