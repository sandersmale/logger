# Radiologger Deployment Instructies

Dit document beschrijft stap voor stap hoe je de Radiologger applicatie kunt deployen op een Digital Ocean VPS.

## Stap 1: Repository op GitHub maken

1. Ga naar [GitHub](https://github.com) en log in op je account
2. Klik rechtsboven op het '+' icoon en kies "New repository"
3. Vul de repository naam in, bijv. "radiologger"
4. Kies 'Private' als je de code privé wilt houden
5. Klik op "Create repository"

## Stap 2: Code naar GitHub pushen

Voer deze commando's uit in je lokale ontwikkelomgeving waar je de code hebt:

```bash
# Initialiseer Git in de projectmap (overslaan als je al git gebruikt)
cd /pad/naar/radiologger
git init

# Voeg alle bestanden toe
git add .

# Maak een requirements.txt bestand (als je export_requirements.txt hebt)
cp export_requirements.txt requirements.txt
git add requirements.txt

# Commit de bestanden
git commit -m "Initiële commit van Radiologger applicatie"

# Voeg de remote repository toe (vervang USERNAME door je GitHub gebruikersnaam)
git remote add origin https://github.com/USERNAME/radiologger.git

# Push naar GitHub
git push -u origin main
```

## Stap 3: Verbinding maken met de Digital Ocean VPS

```bash
# SSH verbinding maken (vervang het IP-adres door jouw VPS IP)
ssh root@68.183.3.122
```

## Stap 4: Benodigde software installeren op de VPS

```bash
# Systeem updaten
apt update
apt upgrade -y

# Benodigde pakketten installeren
apt install -y python3 python3-pip python3-venv 
apt install -y postgresql postgresql-contrib 
apt install -y ffmpeg
apt install -y nginx
apt install -y certbot python3-certbot-nginx
apt install -y build-essential libpq-dev git

# Firewall instellen (optioneel)
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw enable
```

## Stap 5: PostgreSQL database instellen

```bash
# PostgreSQL gebruiker en database aanmaken
sudo -u postgres psql -c "CREATE USER radiologger WITH PASSWORD 'KIES_EEN_STERK_WACHTWOORD';"
sudo -u postgres psql -c "CREATE DATABASE radiologger OWNER radiologger;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE radiologger TO radiologger;"
```

## Stap 6: Radiologger gebruiker aanmaken en mapstructuur opzetten

```bash
# Maak een radiologger gebruiker aan
useradd -m -s /bin/bash radiologger

# Maak de benodigde mappen aan
mkdir -p /opt/radiologger
mkdir -p /var/log/radiologger
mkdir -p /var/lib/radiologger/recordings

# Stel het eigenaarschap van de mappen in
chown -R radiologger:radiologger /opt/radiologger
chown -R radiologger:radiologger /var/log/radiologger
chown -R radiologger:radiologger /var/lib/radiologger
```

## Stap 7: Code klonen vanaf GitHub

```bash
# Clone de repository (vervang USERNAME door je GitHub gebruikersnaam)
git clone https://github.com/USERNAME/radiologger.git /opt/radiologger

# Stel eigenaarschap in
chown -R radiologger:radiologger /opt/radiologger
```

## Stap 8: Python virtuele omgeving en dependencies installeren

```bash
cd /opt/radiologger
python3 -m venv venv
/opt/radiologger/venv/bin/pip install --upgrade pip
/opt/radiologger/venv/bin/pip install -r requirements.txt
```

## Stap 9: Configuratie bestand maken

Maak een `.env` bestand in de `/opt/radiologger` map:

```bash
cat > /opt/radiologger/.env << 'EOL'
FLASK_APP=main.py
FLASK_ENV=production
DATABASE_URL=postgresql://radiologger:KIES_EEN_STERK_WACHTWOORD@localhost:5432/radiologger
FLASK_SECRET_KEY=GENEREER_EEN_VEILIGE_SLEUTEL
WASABI_ACCESS_KEY=jouw_wasabi_access_key
WASABI_SECRET_KEY=jouw_wasabi_secret_key
WASABI_BUCKET=jouw_wasabi_bucket_naam
WASABI_REGION=eu-central-1
WASABI_ENDPOINT_URL=https://s3.eu-central-1.wasabisys.com
RECORDINGS_DIR=/var/lib/radiologger/recordings
LOGS_DIR=/var/log/radiologger
RETENTION_DAYS=30
DENNIS_API_URL=https://url-naar-dennis-api/
OMROEP_LVC_URL=https://url-naar-omroep-lvc/
EOL

# Pas de rechten aan
chown radiologger:radiologger /opt/radiologger/.env
chmod 600 /opt/radiologger/.env
```

## Stap 10: Database migraties uitvoeren en basisgegevens toevoegen

```bash
cd /opt/radiologger
sudo -u radiologger /opt/radiologger/venv/bin/python setup_db.py
```

## Stap 11: Systemd service configureren

```bash
cat > /etc/systemd/system/radiologger.service << 'EOL'
[Unit]
Description=Radiologger Web Application
After=network.target postgresql.service

[Service]
User=radiologger
Group=radiologger
WorkingDirectory=/opt/radiologger
Environment="PATH=/opt/radiologger/venv/bin"
EnvironmentFile=/opt/radiologger/.env
ExecStart=/opt/radiologger/venv/bin/gunicorn --workers 3 --bind 0.0.0.0:5000 --log-level=info --access-logfile=/var/log/radiologger/access.log --error-logfile=/var/log/radiologger/error.log main:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Systemd service activeren
systemctl daemon-reload
systemctl enable radiologger
systemctl start radiologger
```

## Stap 12: Nginx configureren

```bash
cat > /etc/nginx/sites-available/radiologger << 'EOL'
server {
    listen 80;
    server_name logger.pilotradio.nl;

    access_log /var/log/nginx/radiologger_access.log;
    error_log /var/log/nginx/radiologger_error.log;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Websocket support (voor toekomstige functionaliteit)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts instellen voor lange requests
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }

    # Sta grote uploads toe voor audiobestanden
    client_max_body_size 100M;
}
EOL

# Nginx site activeren
ln -s /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default  # Verwijder default site
nginx -t  # Configuratie testen
systemctl restart nginx
```

## Stap 13: SSL certificaat instellen met Let's Encrypt

```bash
certbot --nginx -d logger.pilotradio.nl

# Volg de instructies op het scherm
# Kies voor automatische redirect van HTTP naar HTTPS
```

## Stap 14: Automatische updates en onderhoud

```bash
# Cron-taken instellen voor onderhoud
crontab -e
```

Voeg de volgende regels toe:

```
# Elke dag om 2:00 oude logbestanden verwijderen (ouder dan 30 dagen)
0 2 * * * find /var/log/radiologger -name "*.log" -type f -mtime +30 -delete

# Elke week op zondag om 3:00 systeemupdates uitvoeren
0 3 * * 0 apt update && apt upgrade -y
```

## Stap 15: Testen van de installatie

Test of de applicatie correct werkt:

1. Open een browser en ga naar https://logger.pilotradio.nl
2. Login met de standaard admin gebruiker:
   - Gebruikersnaam: admin
   - Wachtwoord: radioadmin (verander dit direct na inloggen!)

## Probleemoplossing

### Applicatie logs controleren

```bash
# Web applicatie logs
tail -f /var/log/radiologger/error.log
tail -f /var/log/radiologger/access.log

# Systemd service logs
journalctl -u radiologger.service

# Nginx logs
tail -f /var/log/nginx/radiologger_error.log
tail -f /var/log/nginx/radiologger_access.log
```

### Services herstarten

```bash
# Radiologger service herstarten
systemctl restart radiologger

# Nginx herstarten
systemctl restart nginx

# PostgreSQL herstarten
systemctl restart postgresql
```

### Database problemen

```bash
# PostgreSQL console openen
sudo -u postgres psql radiologger

# Controle of de tabellen bestaan
\dt

# Afsluiten
\q
```

## Updates toepassen

Wanneer je de code update, volg dan deze stappen:

```bash
# Nieuwe code binnenhalen
cd /opt/radiologger
git pull

# Installeer eventuele nieuwe dependencies
/opt/radiologger/venv/bin/pip install -r requirements.txt

# Voer database migraties uit (indien nodig)
sudo -u radiologger /opt/radiologger/venv/bin/flask db upgrade

# Herstart de service
systemctl restart radiologger
```

## Veiligheidstips

1. Verander direct de standaard wachtwoorden
2. Houd het systeem up-to-date met regelmatige updates
3. Overweeg een firewall (UFW) te configureren om alleen de benodigde poorten open te zetten
4. Stel een SSL certificaat in via Let's Encrypt
5. Maak regelmatig backups van de database