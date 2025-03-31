# Eenvoudige installatie-instructies voor Radiologger

Deze instructies zorgen voor een eenvoudige en foutbestendige installatie van Radiologger, met automatische controle en herstel van missende componenten.

> **Belangrijke update**: Nu compatible met Ubuntu 24.04 LTS! Het installatiescript detecteert automatisch Ubuntu 24.04 en gebruikt de vereiste `--break-system-packages` flag voor pip installaties.

## Eén-commando installatie (aanbevolen)

Kopieer en plak het volgende commando om Radiologger volledig te installeren:

```bash
sudo bash -c 'apt update && apt install -y git apache2 curl python3 python3-venv python3-pip ffmpeg postgresql libapache2-mod-wsgi-py3 libxml2-dev postgresql-contrib build-essential libpq-dev libcurl4-openssl-dev libssl-dev python3-boto3 certbot python3-certbot-apache net-tools wget && mkdir -p /tmp/radiologger && cd /tmp/radiologger && git clone https://github.com/sandersmale/logger.git . && a2enmod proxy proxy_http proxy_balancer proxy_connect proxy_html xml2enc rewrite headers ssl && systemctl restart apache2 && chmod +x ./install.sh && ./install.sh'
```

Dit commando doet alles in één keer:
1. Installeert alle benodigde systeem pakketten
2. Maakt een tijdelijke map aan en downloadt de installatie bestanden
3. Activeert de benodigde Apache modules
4. Voert het installatiescript uit met volautomatische foutdetectie en herstel

### Verbeterde installatie met:
- Automatische detectie en download van missende bestanden
- Meerdere download methoden als fallback
- Betere foutafhandeling en herstel van installatiefouten
- Uitgebreide logregistratie voor probleemoplossing

## Stapsgewijze installatie (alternatief)

Als je liever stap voor stap installeert:

### Stap 1: Installeer benodigde pakketten

```bash
sudo apt update && sudo apt install -y git apache2 curl python3 python3-venv python3-pip ffmpeg postgresql libapache2-mod-wsgi-py3 libxml2-dev postgresql-contrib build-essential libpq-dev libcurl4-openssl-dev libssl-dev python3-boto3 certbot python3-certbot-apache net-tools wget
```

### Stap 2: Activeer Apache modules

```bash
sudo a2enmod proxy proxy_http proxy_balancer proxy_connect proxy_html xml2enc rewrite headers ssl
sudo systemctl restart apache2
```

### Stap 3: Download en installeer Radiologger

```bash
sudo mkdir -p /tmp/radiologger && cd /tmp/radiologger
sudo git clone https://github.com/sandersmale/logger.git .
sudo chmod +x ./install.sh
sudo ./install.sh
```

## Toegang tot de webinterface

Na de installatie kun je Radiologger bereiken via:
- http://[jouw-server-ip] of https://[jouw-domeinnaam] (als SSL is geconfigureerd)

Bij de eerste keer openen van de webinterface hoef je alleen nog maar:
1. Een admin account aan te maken

De Wasabi S3-configuratie is al tijdens de installatie ingesteld (het script vraagt om deze gegevens). Je kunt deze configuratie later aanpassen in het admin dashboard als dat nodig is.

## Troubleshooting

### Ubuntu 24.04 specifieke problemen

Bij Ubuntu 24.04 kun je deze foutmelding zien: `error: externally-managed-environment`. Dit komt door een verandering in hoe Python packages beheert. Het installatiescript detecteert dit automatisch en lost het op met de `--break-system-packages` flag. 

Als je problemen ondervindt met de installatie op Ubuntu 24.04, gebruik het speciale diagnose script:

```bash
sudo bash /opt/radiologger/diagnose_ubuntu24.sh
```

Dit script detecteert en lost de meest voorkomende problemen automatisch op. Als je toch handmatig wilt ingrijpen, kun je dit doen:

```bash
cd /opt/radiologger
source venv/bin/activate
pip install -r requirements.txt --break-system-packages
deactivate
sudo systemctl restart radiologger
```

### Algemene problemen

Als je andere problemen ondervindt, gebruik de volgende commando's:

### Controleer installatiestatus
```bash
# Toon gekleurde, gedetailleerde installatie logs
sudo cat /tmp/radiologger_install.log
sudo cat /tmp/radiologger_install_error.log

# Controleer service status
sudo systemctl status radiologger
sudo systemctl status apache2
sudo systemctl status postgresql
```

### Veelvoorkomende problemen oplossen
```bash
# Controleer applicatie logs
sudo tail -f /var/log/radiologger/error.log
sudo tail -f /var/log/apache2/error.log
sudo journalctl -u radiologger --no-pager -n 50

# Herstel permissies indien nodig
sudo bash /opt/radiologger/fix_permissions.sh

# Start de service opnieuw
sudo systemctl restart radiologger

# Controleer database status
sudo -u postgres psql -c "\l" | grep radiologger
```

### Als database problemen blijven bestaan
```bash
# Reset de database compleet (waarschuwing: verwijdert alle gegevens!)
cd /opt/radiologger
sudo -u radiologger bash -c "source venv/bin/activate && python reset_db.py && deactivate"
```

### Controleer of de flask app correct werkt
```bash
# Test de Flask app direct
cd /opt/radiologger
sudo -u radiologger bash -c "source venv/bin/activate && python main.py && deactivate"
```