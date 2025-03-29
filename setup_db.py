#!/usr/bin/env python3
"""
Dit script initialiseert de database met basisgegevens 
voor de radiologger applicatie.
"""

import os
import sys
import logging
from datetime import datetime
from werkzeug.security import generate_password_hash

# Configureer logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Zorg ervoor dat we de app kunnen importeren
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

# Importeer de app en database modellen
from app import app, db
from models import User, Station, DennisStation

def setup_database():
    """
    Initialiseer de database en voeg de basis gebruikers toe.
    """
    with app.app_context():
        # Database tabellen aanmaken
        logger.info("Database tabellen worden aangemaakt...")
        db.create_all()
        
        # Default gebruikers toevoegen als ze niet bestaan
        if User.query.filter_by(username='admin').first() is None:
            admin = User(
                username='admin',
                role='admin'
            )
            admin.set_password('radioadmin')
            db.session.add(admin)
            logger.info("Admin gebruiker toegevoegd")
        
        if User.query.filter_by(username='editor').first() is None:
            editor = User(
                username='editor',
                role='editor'
            )
            editor.set_password('radioeditor')
            db.session.add(editor)
            logger.info("Editor gebruiker toegevoegd")
        
        if User.query.filter_by(username='luisteraar').first() is None:
            listener = User(
                username='luisteraar',
                role='listener'
            )
            listener.set_password('radioluisteraar')
            db.session.add(listener)
            logger.info("Luisteraar gebruiker toegevoegd")
        
        # Standaard Dennis stations toevoegen
        add_default_dennis_stations()
        
        # Wijzigingen opslaan
        db.session.commit()
        logger.info("Database setup succesvol voltooid!")

def add_default_dennis_stations():
    """Voeg standaard Dennis stations toe als ze niet bestaan"""
    dennis_stations = [
        {
            "folder": "radio1",
            "name": "NPO Radio 1",
            "url": "https://icecast.omroep.nl/radio1-bb-mp3",
            "visible": True
        },
        {
            "folder": "radio2",
            "name": "NPO Radio 2",
            "url": "https://icecast.omroep.nl/radio2-bb-mp3",
            "visible": True
        },
        {
            "folder": "3fm",
            "name": "NPO 3FM",
            "url": "https://icecast.omroep.nl/3fm-bb-mp3",
            "visible": True
        },
        {
            "folder": "klassiek",
            "name": "NPO Klassiek",
            "url": "https://icecast.omroep.nl/radio4-bb-mp3",
            "visible": True
        },
        {
            "folder": "radio5",
            "name": "NPO Radio 5",
            "url": "https://icecast.omroep.nl/radio5-bb-mp3",
            "visible": True
        },
        {
            "folder": "funx",
            "name": "FunX",
            "url": "https://icecast.omroep.nl/funx-bb-mp3",
            "visible": True
        },
        {
            "folder": "bnr",
            "name": "BNR Nieuwsradio",
            "url": "https://stream.bnr.nl/bnr_mp3_128_20",
            "visible": True
        },
        {
            "folder": "skyradio",
            "name": "Sky Radio",
            "url": "https://23043.live.streamtheworld.com/SKYRADIO.mp3",
            "visible": True
        },
        {
            "folder": "radio538",
            "name": "Radio 538",
            "url": "https://21253.live.streamtheworld.com/RADIO538.mp3",
            "visible": True
        },
        {
            "folder": "radio10",
            "name": "Radio 10",
            "url": "https://23693.live.streamtheworld.com/RADIO10.mp3",
            "visible": True
        },
        {
            "folder": "qmusic",
            "name": "Qmusic",
            "url": "https://stream.qmusic.nl/qmusic/mp3",
            "visible": True
        },
        {
            "folder": "100nl",
            "name": "100% NL",
            "url": "https://stream.100p.nl/100pctnl.mp3",
            "visible": True
        },
        {
            "folder": "veronica",
            "name": "Radio Veronica",
            "url": "https://20873.live.streamtheworld.com/VERONICA.mp3",
            "visible": True
        },
        {
            "folder": "sublime",
            "name": "Sublime",
            "url": "https://25303.live.streamtheworld.com/SUBLIME.mp3",
            "visible": True
        }
    ]
        {
            "folder": "radio2",
            "name": "NPO Radio 2",
            "url": "https://icecast.omroep.nl/radio2-bb-mp3",
            "visible": True
        },
        {
            "folder": "radio3",
            "name": "NPO 3FM",
            "url": "https://icecast.omroep.nl/3fm-bb-mp3",
            "visible": True
        },
        {
            "folder": "radio4",
            "name": "NPO Radio 4",
            "url": "https://icecast.omroep.nl/radio4-bb-mp3",
            "visible": True
        },
        {
            "folder": "radio5",
            "name": "NPO Radio 5",
            "url": "https://icecast.omroep.nl/radio5-bb-mp3",
            "visible": True
        },
        {
            "folder": "funx",
            "name": "FunX",
            "url": "https://icecast.omroep.nl/funx-bb-mp3",
            "visible": True
        },
        {
            "folder": "bnr",
            "name": "BNR Nieuwsradio",
            "url": "https://stream.bnr.nl/bnr_mp3_128_03",
            "visible": True
        },
        {
            "folder": "skyradio",
            "name": "Sky Radio",
            "url": "https://19993.live.streamtheworld.com/SKYRADIO.mp3",
            "visible": True
        },
        {
            "folder": "radio538",
            "name": "Radio 538",
            "url": "https://21253.live.streamtheworld.com/RADIO538.mp3",
            "visible": True
        },
        {
            "folder": "radio10",
            "name": "Radio 10",
            "url": "https://20873.live.streamtheworld.com/RADIO10.mp3",
            "visible": True
        },
        {
            "folder": "qmusic",
            "name": "Qmusic",
            "url": "https://stream.qmusic.nl/qmusic/mp3",
            "visible": True
        },
        {
            "folder": "100nl",
            "name": "100% NL",
            "url": "https://stream.100p.nl/100pctnl.mp3",
            "visible": True
        },
        {
            "folder": "veronica",
            "name": "Radio Veronica",
            "url": "https://20873.live.streamtheworld.com/VERONICA.mp3",
            "visible": True
        },
        {
            "folder": "sublime",
            "name": "Sublime FM",
            "url": "https://stream.sublimefm.nl/mp3",
            "visible": True
        }
    ]
    
    added = 0
    updated = 0
    
    for station_data in dennis_stations:
        folder = station_data["folder"]
        name = station_data["name"]
        url = station_data["url"]
        visible = station_data["visible"]
        
        # Controleer of station bestaat
        station = DennisStation.query.filter_by(folder=folder).first()
        
        if station:
            # Update bestaand station
            station.name = name
            station.url = url
            station.visible_in_logger = visible
            station.last_updated = datetime.utcnow()
            updated += 1
        else:
            # Nieuw station toevoegen
            station = DennisStation(
                folder=folder,
                name=name,
                url=url,
                visible_in_logger=visible,
                last_updated=datetime.utcnow()
            )
            db.session.add(station)
            added += 1
    
    logger.info(f"Dennis stations: {added} toegevoegd, {updated} bijgewerkt")

if __name__ == "__main__":
    logger.info("Start database initialisatie...")
    setup_database()