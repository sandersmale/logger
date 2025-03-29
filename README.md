# Radiologger

Een moderne Python/Flask applicatie voor het opnemen, beheren en afspelen van radio-uitzendingen. 

## Functionaliteit

- Opnemen van radio streams met automatische segmentatie per uur
- Beheer van lokale stations en integratie met externe stations via de Dennis API
- Upload van opnames naar Wasabi S3 object storage
- Gebruikersbeheer met verschillende toegangsniveaus (admin, editor, listener)
- Gebruiksvriendelijke web interface voor het beluisteren van opnames
- Volledig toegankelijk voor screen readers (NVDA, JAWS, VoiceOver)

## Technische details

- Backend: Python 3.11+ met Flask framework
- Database: PostgreSQL
- Audio opname: FFmpeg
- Cloud storage: Wasabi/S3 compatible storage
- Web server: Nginx met Gunicorn

## Installatie

Voor gedetailleerde installatie-instructies, zie:

- [INSTALL.md](INSTALL.md) - Uitgebreide installatie handleiding
- [deploy_instructions.md](deploy_instructions.md) - Stap-voor-stap deployment instructies

Je kunt ook het meegeleverde installatiescript gebruiken:

```bash
sudo ./install.sh
```

## Configuratie

Alle configuratie-instellingen worden gelezen uit het `.env` bestand in de hoofdmap van het project. 
Zie het voorbeeldbestand voor de beschikbare opties.

## Beveiliging

- De applicatie gebruikt Flask-Login voor authenticatie
- Wachtwoorden worden gehashed opgeslagen met Werkzeug security
- De applicatie ondersteunt HTTPS via Let's Encrypt certificaten
- CSRF bescherming is ingeschakeld met Flask-WTF

## Ontwikkeling

Voor ontwikkelaars is er een speciale ontwikkelingsmodus:

```bash
# Set environment
export FLASK_ENV=development
export FLASK_APP=main.py

# Run development server
flask run --host=0.0.0.0
```

## Licentie

Zie het LICENSE bestand voor licentiedetails.