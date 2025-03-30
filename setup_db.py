#!/usr/bin/env python3
"""
Dit script initialiseert de database met basisgegevens 
voor de radiologger applicatie.
"""
import sys
import os
import logging
import json
from datetime import datetime
from werkzeug.security import generate_password_hash

# Configuratie voor logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Zorg ervoor dat we de applicatie kunnen importeren
current_dir = os.path.abspath(os.getcwd() or '.')
sys.path.insert(0, current_dir)

# Probeer de applicatie te importeren, met robuuste foutafhandeling
try:
    from app import db, app
    from models import User, Station, DennisStation
except ImportError as e:
    logger.error(f"Kon app of models niet importeren: {e}")
    logger.info("Controleren of we in de juiste map zitten...")
    
    # Kijk of we in de projectmap zijn of in een andere map
    project_files = ['app.py', 'models.py', 'config.py']
    missing_files = [f for f in project_files if not os.path.exists(os.path.join(current_dir, f))]
    
    if missing_files:
        logger.error(f"Missende bestanden in huidige map: {', '.join(missing_files)}")
        logger.info("Probeer dit script vanuit de hoofdmap van het project uit te voeren")
        print(f"❌ Fout: kan benodigde bestanden niet vinden: {', '.join(missing_files)}")
        print("Zorg dat u dit script vanuit de hoofdmap van het project uitvoert")
        sys.exit(1)
    else:
        # Als bestanden bestaan maar import nog steeds faalt
        logger.error("Bestanden gevonden maar import mislukt. Controleer de Python omgeving.")
        print("❌ Fout: bestanden gevonden maar import mislukt. Python-omgeving probleem?")
        sys.exit(1)

def setup_database():
    """
    Initialiseer de database en voeg de basis gebruikers toe.
    """
    try:
        # Maak de tabellen aan als ze niet bestaan
        with app.app_context():
            db.create_all()
            logger.info("Database tabellen aangemaakt")

        # Controleer of er al gebruikers bestaan, zo niet, maak standaard gebruikers
        with app.app_context():
            if User.query.count() == 0:
                logger.info("Aanmaken standaard gebruikers")
                
                # Admin gebruiker
                admin = User(username='admin', role='admin')
                admin.set_password('radioadmin')
                db.session.add(admin)
                
                # Editor gebruiker
                editor = User(username='editor', role='editor')
                editor.set_password('radioeditor')
                db.session.add(editor)
                
                # Luisteraar gebruiker
                listener = User(username='luisteraar', role='listener')
                listener.set_password('radioluisteraar')
                db.session.add(listener)
                
                db.session.commit()
                logger.info("Standaard gebruikers aangemaakt")
            else:
                logger.info("Gebruikers bestaan al, geen nieuwe gebruikers aangemaakt")
        
            # Voeg standaard Dennis stations toe als ze nog niet bestaan
            add_default_dennis_stations()
            
            # Voeg standaard stations toe als ze nog niet bestaan
            use_default_stations = "--use-default-stations" in sys.argv
            if Station.query.count() == 0:
                if use_default_stations and os.path.exists('default_stations.json'):
                    logger.info("Importeren standaard stations uit default_stations.json")
                    with open('default_stations.json', 'r') as f:
                        stations_data = json.load(f)
                    
                    for idx, station_data in enumerate(stations_data):
                        station = Station(
                            name=station_data['name'],
                            recording_url=station_data['recording_url'],
                            always_on=station_data.get('always_on', False),
                            display_order=idx
                        )
                        db.session.add(station)
                    
                    db.session.commit()
                    logger.info(f"{len(stations_data)} standaard stations geïmporteerd")
                else:
                    # Voeg enkele voorbeeld stations toe
                    logger.info("Toevoegen van voorbeeld radiostations")
                    stations = [
                        Station(name="NPO Radio 1", recording_url="https://icecast.omroep.nl/radio1-bb-mp3", display_order=1),
                        Station(name="NPO Radio 2", recording_url="https://icecast.omroep.nl/radio2-bb-mp3", display_order=2),
                        Station(name="NPO 3FM", recording_url="https://icecast.omroep.nl/3fm-bb-mp3", display_order=3),
                        Station(name="NPO Radio 4", recording_url="https://icecast.omroep.nl/radio4-bb-mp3", display_order=4),
                        Station(name="NPO Radio 5", recording_url="https://icecast.omroep.nl/radio5-bb-mp3", display_order=5),
                        Station(name="Omroep LvC", recording_url="https://stream.omroeplvc.nl:8006/radio", display_order=6)
                    ]
                    for station in stations:
                        db.session.add(station)
                    
                    db.session.commit()
                    logger.info("Voorbeeld stations toegevoegd")
            else:
                logger.info("Stations bestaan al, geen nieuwe stations toegevoegd")

        logger.info("Database initialisatie voltooid")
        return True
    except Exception as e:
        logger.error(f"Fout bij database initialisatie: {str(e)}")
        return False

def add_default_dennis_stations():
    """Voeg Dennis stations toe van de API"""
    try:
        # Dit wordt reeds binnen app.app_context aangeroepen door de hoofdfunctie
        # dus we hoeven niet nog een keer app.app_context() te gebruiken
        if DennisStation.query.count() == 0:
            logger.info("Ophalen en toevoegen van Dennis stations van de API")
            
            # Importeer de refresh_dennis_api functie uit api_integrations
            try:
                from api_integrations import refresh_dennis_api
                
                # Roep de functie aan om de Dennis API data op te halen
                result = refresh_dennis_api()
                
                if result['success']:
                    logger.info(f"Dennis API data succesvol opgehaald: {result['added']} stations toegevoegd, {result['updated']} bijgewerkt")
                    return True
                else:
                    logger.error(f"Fout bij ophalen Dennis API data: {result['error']}")
                    # Ga door met fallback hieronder als API ophalen mislukt
            except Exception as import_error:
                logger.error(f"Kon refresh_dennis_api niet importeren of uitvoeren: {import_error}")
                
            # Fallback: voeg standaard stations toe als de API niet beschikbaar is
            logger.warning("Gebruik fallback lijst van Dennis stations")
            dennis_stations = [
                {"folder": "1001", "name": "Radio 10", "url": "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO10.mp3"},
                {"folder": "538", "name": "Radio 538", "url": "https://playerservices.streamtheworld.com/api/livestream-redirect/RADIO538.mp3"},
                {"folder": "100nl", "name": "100% NL", "url": "https://stream.100p.nl/100pctnl.mp3"},
                {"folder": "Qmusic", "name": "Qmusic", "url": "https://stream.qmusic.nl/qmusic/mp3"},
                {"folder": "Sky", "name": "Sky Radio", "url": "https://playerservices.streamtheworld.com/api/livestream-redirect/SKYRADIO.mp3"}
            ]
            
            for station_data in dennis_stations:
                station = DennisStation(
                    folder=station_data["folder"],
                    name=station_data["name"],
                    url=station_data["url"],
                    visible_in_logger=False
                )
                db.session.add(station)
            
            db.session.commit()
            logger.info(f"{len(dennis_stations)} fallback Dennis stations toegevoegd")
        else:
            logger.info("Dennis stations bestaan al")
        return True
    except Exception as e:
        logger.error(f"Fout bij toevoegen Dennis stations: {str(e)}")
        return False

if __name__ == "__main__":
    # Voer de setup uit
    if setup_database():
        print("✅ Database succesvol geïnitialiseerd")
        sys.exit(0)
    else:
        print("❌ Database initialisatie mislukt")
        sys.exit(1)