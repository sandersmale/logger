# Radiologger Installatie Instructies

Deze instructies helpen je bij het installeren van de Radiologger applicatie op een Ubuntu 24.04 VPS.

## Systeemvereisten

- Ubuntu 24.04 LTS
- Python 3.11+
- PostgreSQL 15+
- FFmpeg 5.1+
- Nginx

## Stap 1: Systeem voorbereiden

```bash
# Systeem updaten
sudo apt update
sudo apt upgrade -y

# Installeer benodigde systeempakketten
sudo apt install -y python3 python3-pip python3-venv 
sudo apt install -y postgresql postgresql-contrib
sudo apt install -y ffmpeg
sudo apt install -y nginx
sudo apt install -y certbot python3-certbot-nginx
sudo apt install -y build-essential libpq-dev
```

## Stap 2: PostgreSQL database instellen

```bash
# PostgreSQL instellen
sudo -u postgres psql -c "CREATE USER radiologger WITH PASSWORD 'wachtwoord';"
sudo -u postgres psql -c "CREATE DATABASE radiologger OWNER radiologger;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE radiologger TO radiologger;"
```

## Stap 3: Applicatiecode installeren

```bash
# Map aanmaken en eigenaarschap instellen
sudo mkdir -p /opt/radiologger
sudo mkdir -p /var/log/radiologger
sudo mkdir -p /var/lib/radiologger/recordings

# Applicatiecode kopiëren (pas aan voor jouw situatie)
# Optie 1: Vanaf een Git repository
# git clone https://github.com/jouw-username/radiologger.git /opt/radiologger
# Optie 2: Upload via SCP/SFTP

# Eigenaarschap instellen (we gaan uit van een 'radiologger' gebruiker)
sudo useradd -m -s /bin/bash radiologger
sudo chown -R radiologger:radiologger /opt/radiologger
sudo chown -R radiologger:radiologger /var/log/radiologger
sudo chown -R radiologger:radiologger /var/lib/radiologger
```

## Stap 4: Python virtuele omgeving en dependencies installeren

```bash
cd /opt/radiologger
sudo -u radiologger python3 -m venv venv
sudo -u radiologger venv/bin/pip install -r requirements.txt
sudo -u radiologger venv/bin/pip install gunicorn
```

## Stap 5: Configuratie

Maak een `.env` bestand aan in de `/opt/radiologger` map:

```bash
sudo -u radiologger nano /opt/radiologger/.env
```

Voeg de volgende variabelen toe (pas aan waar nodig):

```
FLASK_APP=main.py
FLASK_ENV=production
DATABASE_URL=postgresql://radiologger:wachtwoord@localhost:5432/radiologger
FLASK_SECRET_KEY=eenZeerGeheimeSleutel
WASABI_ACCESS_KEY=jouw_wasabi_access_key
WASABI_SECRET_KEY=jouw_wasabi_secret_key
WASABI_BUCKET=jouw_wasabi_bucket_naam
WASABI_REGION=eu-central-1
RECORDINGS_DIR=/var/lib/radiologger/recordings
LOGS_DIR=/var/log/radiologger
RETENTION_DAYS=30
OMROEP_LVC_URL=http://url-naar-omroep-lvc/
```

## Stap 6: Systemd service configureren

Maak een systemd service bestand aan:

```bash
sudo nano /etc/systemd/system/radiologger.service
```

Met de volgende inhoud:

```ini
[Unit]
Description=Radiologger Web Application
After=network.target postgresql.service

[Service]
User=radiologger
Group=radiologger
WorkingDirectory=/opt/radiologger
Environment="PATH=/opt/radiologger/venv/bin"
EnvironmentFile=/opt/radiologger/.env
ExecStart=/opt/radiologger/venv/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 main:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Activeer en start de service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable radiologger
sudo systemctl start radiologger
```

## Stap 7: Nginx als reverse proxy configureren

Maak een Nginx configuratiebestand:

```bash
sudo nano /etc/nginx/sites-available/radiologger
```

Met de volgende inhoud:

```nginx
server {
    listen 80;
    server_name logger.pilotradio.nl;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Activeer de site en herstart Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/radiologger /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Stap 8: SSL certificaat instellen met Let's Encrypt

```bash
sudo certbot --nginx -d logger.pilotradio.nl
```

## Stap 9: Database vullen met initiële data

```bash
cd /opt/radiologger
sudo -u radiologger venv/bin/python setup_db.py
```

## Stap 10: Monitoring instellen

Voor basismonitoring van de applicatie:

```bash
sudo apt install -y prometheus-node-exporter
```

## Extra: Automatische updates en onderhoud

Voeg deze CRON-taken toe om periodiek schijfruimte te controleren en oude log bestanden op te ruimen:

```bash
sudo crontab -e
```

Voeg toe:

```
# Elke dag om 2:00 oude logbestanden verwijderen (ouder dan 30 dagen)
0 2 * * * find /var/log/radiologger -name "*.log" -type f -mtime +30 -delete

# Elke week op zondag om 3:00 systeemupdates uitvoeren
0 3 * * 0 apt update && apt upgrade -y
```

## Probleemoplossing

### Log bestanden controleren
```bash
# Radiologger logs
tail -f /var/log/radiologger/radiologger.log

# Systemd service logs
journalctl -u radiologger.service

# Nginx logs
tail -f /var/log/nginx/error.log
tail -f /var/log/nginx/access.log
```

### Herstart services
```bash
sudo systemctl restart radiologger
sudo systemctl restart nginx
sudo systemctl restart postgresql
```

### Controle of services draaien
```bash
sudo systemctl status radiologger
sudo systemctl status nginx
sudo systemctl status postgresql
```