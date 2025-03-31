# Eenvoudige installatie-instructies voor Radiologger

Deze instructies zorgen voor een eenvoudige en foutloze installatie van Radiologger.

## Eén-commando installatie

Kopieer en plak het volgende commando om Radiologger volledig te installeren:

```bash
sudo bash -c 'apt update && apt install -y git apache2 curl python3 python3-venv python3-pip ffmpeg postgresql libapache2-mod-wsgi-py3 libxml2-dev postgresql-contrib build-essential libpq-dev libcurl4-openssl-dev libssl-dev python3-boto3 certbot python3-certbot-apache net-tools wget && mkdir -p /tmp/radiologger && cd /tmp/radiologger && git clone https://github.com/sandersmale/logger.git . && a2enmod proxy proxy_http proxy_balancer proxy_connect proxy_html xml2enc rewrite headers ssl && systemctl restart apache2 && chmod +x ./install.sh && ./install.sh'
```

Dit commando doet alles in één keer:
1. Installeert alle benodigde systeem pakketten
2. Maakt een tijdelijke map aan en downloadt alle bestanden van GitHub
3. Activeert de benodigde Apache modules
4. Voert het installatiescript uit

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

Bij de eerste keer openen, word je gevraagd om:
1. Een admin account aan te maken
2. Wasabi S3 opslag te configureren

## Troubleshooting

Als je problemen ondervindt, gebruik de volgende commando's:
```bash
# Controleer installatie logs
sudo cat /tmp/radiologger_install.log
sudo cat /tmp/radiologger_install_error.log

# Controleer service status
sudo systemctl status radiologger
sudo systemctl status apache2

# Controleer applicatie logs
sudo tail -f /var/log/radiologger/error.log
sudo tail -f /var/log/apache2/error.log

# Herstel permissies indien nodig
sudo bash /opt/radiologger/fix_permissions.sh
```