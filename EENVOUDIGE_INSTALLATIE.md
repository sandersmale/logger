# Radiologger - Eenvoudige Installatie

Deze handleiding geeft je een simpele, stapsgewijze installatiemethode voor de Radiologger op Ubuntu 22.04/24.04 servers.

## Stap 1: Benodigde software installeren

Eerst moeten we alle benodigde software installeren. Voer dit commando uit als root:

```bash
sudo apt update && sudo apt install -y python3 python3-venv python3-pip ffmpeg apache2 libapache2-mod-proxy-html libapache2-mod-wsgi-py3 postgresql postgresql-contrib git curl wget build-essential libpq-dev
```

Dit installeert:
- Python en benodigde tools
- ffmpeg (voor audio conversie)
- Apache (webserver, betrouwbaarder dan Nginx voor standaardinstallaties)
- PostgreSQL (database)
- Overige benodigde hulpprogramma's

## Stap 2: Radiologger installeren

Nu kun je het installatiescript downloaden en uitvoeren. Dit script zal:
- De Radiologger applicatie downloaden
- Alle nodige bestanden controleren en eventueel ontbrekende bestanden downloaden
- De database instellen
- Services configureren
- Alles starten

Voer uit:

```bash
sudo bash -c "mkdir -p /tmp/radiologger && chmod 700 /tmp/radiologger && cd /tmp/radiologger && wget -O install.sh https://raw.githubusercontent.com/sandersmale/logger/main/install.sh && chmod 700 install.sh && bash install.sh"
```

Tijdens de installatie zul je de volgende zaken moeten invoeren:
1. Een wachtwoord voor de PostgreSQL database gebruiker
2. De domeinnaam van je server (bijvoorbeeld logger.pilotradio.nl)
3. Een e-mailadres voor SSL certificaten
4. Of je standaard radiostations wilt importeren

## Stap 3: Inloggen en configureren

Na de installatie kun je inloggen op de webinterface via je browser:
- http://[jouw-server-ip]

Bij het eerste gebruik moet je:
1. Een administrator account aanmaken
2. De Wasabi S3 opslag configureren (indien gewenst)

## Problemen oplossen

Als je een '502 Bad Gateway' fout ziet, voer dan het diagnose script uit:

```bash
sudo bash /opt/radiologger/diagnose_502.sh
```

Dit script controleert en repareert automatisch veel voorkomende problemen.

## Belangrijke locaties

- Applicatie bestanden: `/opt/radiologger/`
- Log bestanden: `/var/log/radiologger/`
- Opnames: `/var/lib/radiologger/recordings/`
- Database configuratie: `/opt/radiologger/.env`