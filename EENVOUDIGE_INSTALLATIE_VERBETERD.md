# Eenvoudige Installatie voor Radiologger

Dit document beschrijft de eenvoudige installatieprocedure voor Radiologger, een complete radio logging en managementsysteem voor Ubuntu 24.04.

## Installatie in 3 Stappen

### Stap 1: Download en Uitvoeren van het Installatiescript

SSH naar je server en voer de volgende commando's uit:

```bash
# Download installatiescript direct van GitHub
wget -O install.sh https://raw.githubusercontent.com/sandersmale/logger/main/install.sh

# Maak het uitvoerbaar
chmod +x install.sh

# Voer het uit (geen interactie nodig - "rammen met die hap")
./install.sh
```

### Stap 2: Open de Web Interface en Configureer

Na installatie, open een browser en navigeer naar:
- Met domein: `https://jouw-domein.nl`
- Zonder domein: `http://server-ip:5000`

Bij het eerste bezoek zie je de **setup pagina** waar je:
1. Een administrator account kunt aanmaken
2. Eventueel Wasabi S3 opslag kunt configureren

### Stap 3: Voeg Radiostations Toe en Begin met Opnemen

Na het voltooien van de setup en inloggen:
1. Ga naar het "Stations" menu
2. Voeg stations toe of activeer bestaande stations
3. Controleer of opnames correct worden gestart (exact op het hele uur)

## Problemen Oplossen

### Probleem: Setup pagina verschijnt niet (direct login scherm)

Als je direct het login scherm ziet in plaats van de setup pagina:

```bash
# Reset gebruikers om de setup pagina te forceren
cd /opt/radiologger
sudo python reset_users.py

# Herstart de service
sudo systemctl restart radiologger
```

### Probleem: Apache toont standaard pagina in plaats van applicatie

```bash
cd /opt/radiologger
sudo ./fix_apache_config.sh
```

### Probleem: Ubuntu 24.04 pip installatie problemen

```bash
cd /opt/radiologger
sudo ./diagnose_ubuntu24.sh
```

### Probleem: Permissie problemen

```bash
cd /opt/radiologger
sudo ./fix_permissions.sh
```

## Belangrijke Kenmerken

- **Precies-op-het-uur Opnames**: Opnames starten exact op XX:00:00
- **Automatische Uploads**: Opnames worden automatisch naar Wasabi S3 geüpload (elke 15 minuten)
- **Lokale Bestandsretentie**: Bestanden worden direct na upload verwijderd
- **Screenreader Toegankelijkheid**: Interface volledig toegankelijk voor NVDA, JAWS en VoiceOver

## Extra Informatie

Voor uitgebreidere instructies, zie:
- `INSTALL.md` - Volledige technische installatie details
- `EERSTE_GEBRUIK.md` - Meer informatie over eerste gebruik
- `UBUNTU_24_ONDERSTEUNING.md` - Ubuntu 24.04 specifieke informatie