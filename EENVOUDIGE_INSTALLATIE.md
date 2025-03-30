# Radiologger Eenvoudige Installatie Instructies

Deze handleiding beschrijft hoe je Radiologger eenvoudig kunt installeren op een Digital Ocean Ubuntu 24.04 VPS.

## Stap 1: Maak een VPS (Droplet) aan op Digital Ocean

1. Log in op je [Digital Ocean account](https://cloud.digitalocean.com/)
2. Klik op "Create" → "Droplets"
3. Selecteer:
   - **Ubuntu 24.04 (LTS)**
   - Basic plan (minimaal 2GB RAM aanbevolen)
   - Datacenter dichtbij je gebruikers (bijv. Amsterdam)
   - Authenticatie via SSH key of wachtwoord

## Stap 2: Verbind met je VPS

```bash
ssh root@68.183.3.122  # Vervang door jouw IP-adres
```

## Stap 3: Installatie (kies A of B)

### Optie A: Installatie in 3 commando's

```bash
# 1. Maak tijdelijke map en ga er direct naartoe
mkdir -p /tmp/radiologger && cd /tmp/radiologger

# 2. Download het installatiescript direct van GitHub
wget -O install.sh https://raw.githubusercontent.com/sandersmale/logger/main/install.sh

# 3. Maak script uitvoerbaar en start direct de installatie
chmod +x install.sh && sudo ./install.sh
```

### Optie B: Turbo installatie (1 commando, alles-in-één)

```bash
sudo bash -c "mkdir -p /tmp/radiologger && cd /tmp/radiologger && wget -O install.sh https://raw.githubusercontent.com/sandersmale/logger/main/install.sh && chmod +x install.sh && bash install.sh"
```

⚡ Dat is alles! Het script neemt het vanaf hier over.

## Stap 4: Volg de prompts in het script

Het script zal je vragen om enkele gegevens:

1. Bevestiging om door te gaan (type 'j')
2. Database wachtwoord voor de radiologger gebruiker
3. Wasabi credentials:
   - Wasabi access key
   - Wasabi secret key
   - Wasabi bucket naam
   - Wasabi regio (of accepteer de standaardwaarde eu-central-1)
4. Of je een SSL certificaat wilt genereren (aanbevolen, type 'j')

De andere waarden worden automatisch ingesteld:
- De geheime sleutel wordt automatisch gegenereerd
- Dennis API URL is vooraf ingesteld
- Omroep LvC URL is vooraf ingesteld

## Stap 5: Test de installatie

Na succesvolle installatie kun je de applicatie testen:

1. Bezoek `https://logger.pilotradio.nl` of `http://68.183.3.122` in je browser
2. Log in met één van de volgende accounts:
   - Admin: gebruikersnaam: `admin`, wachtwoord: `radioadmin`
   - Editor: gebruikersnaam: `editor`, wachtwoord: `radioeditor`
   - Luisteraar: gebruikersnaam: `luisteraar`, wachtwoord: `radioluisteraar`

**BELANGRIJK:** Verander deze wachtwoorden direct na de eerste inlog!

## Stap 6: DNS configuratie

Zorg dat het domein `logger.pilotradio.nl` naar het IP-adres van je VPS wijst door een A-record in te stellen bij je DNS provider.

## Problemen oplossen

Als je problemen ondervindt tijdens de installatie:

1. Check de logs:
   ```bash
   journalctl -u radiologger
   ```

2. Controleer of de services draaien:
   ```bash
   systemctl status radiologger
   systemctl status nginx
   ```

3. Bekijk de Nginx error logs:
   ```bash
   tail -f /var/log/nginx/error.log
   ```

4. Controleer de applicatie logs:
   ```bash
   tail -f /var/log/radiologger/error.log
   ```

### Als wget niet werkt:
```bash
# Installeer wget eerst
sudo apt update
sudo apt install -y wget
```

### Als het script niet uitvoerbaar is:
```bash
# Controleer of het script is gedownload
ls -l install.sh

# Probeer opnieuw uitvoerbaar te maken
sudo chmod +x install.sh
```

### Als het script faalt:
1. Controleer of je internetverbinding werkt
2. Controleer of je voldoende schijfruimte hebt: `df -h`
3. Bekijk de logbestanden: `tail -f /var/log/radiologger/error.log`

Voor meer gedetailleerde instructies, zie [INSTALL.md](INSTALL.md)

## Systeem updates

Om in de toekomst updates van GitHub te krijgen:

```bash
cd /opt/radiologger
git pull
systemctl restart radiologger