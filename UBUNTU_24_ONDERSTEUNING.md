# Ubuntu 24.04 Ondersteuning

Dit document beschrijft de aanpassingen die zijn gedaan om Radiologger volledig compatibel te maken met Ubuntu 24.04 LTS.

## Belangrijkste veranderingen

### 1. Oplossing voor pip `externally-managed-environment` probleem

Ubuntu 24.04 gebruikt een nieuwe manier van Python package management, waardoor de standaard pip commando's de foutmelding `error: externally-managed-environment` geven. De volgende aanpassingen zijn gemaakt om dit op te lossen:

- Automatische detectie van Ubuntu 24.04 in het installatiescript
- Toevoeging van `--break-system-packages` flag bij alle pip installaties op Ubuntu 24.04
- Verbeterde foutafhandeling en herstelprocedures

### 2. Verbeterde Flask en SQLAlchemy compatibiliteit

- Minimale versievereisten verhoogd naar Flask>=2.2.0 en flask-sqlalchemy>=3.0.0
- Aanpassing van het import-systeem in app.py en main.py om circulaire imports te voorkomen
- Verbeterde logging en debug informatie

### 3. Nieuwe diagnostische functies

- Nieuw diagnose script: `diagnose_ubuntu24.sh` voor automatische probleemoplossing
- Uitgebreidere logging en betere foutmeldingen
- Verbeterde instructies in EENVOUDIGE_INSTALLATIE.md

## Gebruik van diagnose_ubuntu24.sh

Dit script automatiseert de diagnose en het herstel van veelvoorkomende problemen bij installatie op Ubuntu 24.04:

```bash
sudo bash /opt/radiologger/diagnose_ubuntu24.sh
```

Het script voert het volgende uit:
1. Detecteren of het op Ubuntu 24.04 draait
2. Controleren van de Python virtual environment
3. Herstellen van de requirements.txt indien nodig
4. Installeren van dependencies met de juiste flags
5. Controleren en herstellen van bestandspermissies
6. Herstarten van de Radiologger service

## Handmatige stappen (indien nodig)

Als je handmatige Ubuntu 24.04 aanpassingen wilt doen:

```bash
cd /opt/radiologger
source venv/bin/activate
pip install -r requirements.txt --break-system-packages
deactivate
sudo systemctl restart radiologger
```

## Technische details

### Pip install aanpassingen

```bash
# Voor Ubuntu 24.04
pip install -r requirements.txt --break-system-packages

# Voor oudere Ubuntu versies
pip install -r requirements.txt
```

### Dependencies versie-eisen

De minimale versies zijn verhoogd om compatibiliteit te garanderen:

- Flask >= 2.2.0 (voorheen 2.0.1)
- flask-sqlalchemy >= 3.0.0
- Werkzeug >= 2.3.0 (voorheen 2.2.3)

### Import-structuur

De import-structuur is aangepast om circulaire imports te voorkomen:
- main.py importeert nu rechtstreeks 'from app import app'
- Verminderde duplicatie van configuratie tussen app.py en main.py

## Compatibiliteit met oudere versies

Alle aanpassingen zijn volledig backward compatible met oudere Ubuntu versies en productie-implementaties. Het installatiescript detecteert automatisch de Ubuntu-versie en past de juiste commando's toe.