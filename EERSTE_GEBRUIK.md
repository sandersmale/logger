# Radiologger: Eerste Gebruik Instructies

Na de installatie van Radiologger, volg je deze stappen voor de eerste configuratie:

## 1. Open de Web Interface

Open een webbrowser en ga naar:
- Als je een domein hebt geconfigureerd: `https://jouw-domein.nl`
- Anders: `http://server-ip:5000`

## 2. Setup Pagina

Bij het eerste bezoek zie je automatisch de **setup pagina**. Hier kun je:
1. Een administrator account aanmaken
2. Eventueel Wasabi S3 opslag configureren (als dit niet tijdens installatie is gedaan)

![Setup Pagina](https://repository-images.githubusercontent.com/123456789/setup-page-screenshot)

## 3. Aanmelden

Na het afronden van de setup word je automatisch doorgestuurd naar de login pagina. Log in met de administrator account die je zojuist hebt aangemaakt.

## 4. Stations Configureren

Na het inloggen kun je:
- Standaard radiostations bekijken
- Nieuwe stations toevoegen
- Stations van Dennis Media activeren 
- Opnames starten en bekijken

## Problemen Oplossen

Als je **geen setup pagina** ziet maar direct de login pagina, dan zijn er mogelijk al gebruikers in de database aanwezig. In dat geval:

```bash
# Verbind via SSH met je server
ssh gebruiker@jouw-server-ip

# Reset gebruikers om de setup pagina te forceren
cd /opt/radiologger
sudo python reset_users.py

# Herstart de service
sudo systemctl restart radiologger
```

Ververs dan je browser en je zou de setup pagina moeten zien.