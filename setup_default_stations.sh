#!/bin/bash

# setup_default_stations.sh
# Script om standaard radiostations toe te voegen aan Radiologger

# Kleuren voor output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

INSTALL_DIR="/opt/radiologger"
DEFAULT_STATIONS_FILE="$INSTALL_DIR/default_stations.json"

echo -e "${YELLOW}[INFO]${NC} Radiologger standaard stations setup script"

# Controleer of het script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# Controleer of het default_stations.json bestand bestaat
if [ ! -f "$DEFAULT_STATIONS_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} Default stations bestand niet gevonden: $DEFAULT_STATIONS_FILE"
    echo -e "${YELLOW}[FIX]${NC} Aanmaken van default stations bestand..."
    cat > "$DEFAULT_STATIONS_FILE" << 'EOL'
[
    {
        "name": "NPO Radio 1",
        "recording_url": "https://icecast.omroep.nl/radio1-bb-mp3",
        "always_on": false
    },
    {
        "name": "NPO Radio 2",
        "recording_url": "https://icecast.omroep.nl/radio2-bb-mp3",
        "always_on": false
    },
    {
        "name": "Omroep Brabant",
        "recording_url": "https://streaming.omroepbrabant.nl/mp3",
        "always_on": false
    },
    {
        "name": "NH Radio",
        "recording_url": "https://ice.cr2.streamzilla.xlcdn.com:8000/sz=nhnieuws=nhradio_mp3",
        "always_on": false
    },
    {
        "name": "L1 Radio",
        "recording_url": "https://d34pj260kw1xmk.cloudfront.net/icecast/l1/radio-bb-mp3",
        "always_on": false
    },
    {
        "name": "Omroep Zeeland",
        "recording_url": "https://d2e6rqmmd1m3wq.cloudfront.net/icecast/omroepzeeland/radio-mp3",
        "always_on": false
    },
    {
        "name": "RTV NOF",
        "recording_url": "https://broadcast.streamingserver.nl/rtvnof",
        "always_on": false
    },
    {
        "name": "Omroep Venlo",
        "recording_url": "https://olon.az.icecast.ebsd.ericsson.net/omroep_venlo",
        "always_on": false
    },
    {
        "name": "RADIONL Friesland",
        "recording_url": "https://stream.radionl.fm/friesland",
        "always_on": false
    },
    {
        "name": "RADIONL Zuidoost Brabant",
        "recording_url": "https://stream.radionl.fm/zuidoostbrabant",
        "always_on": false
    }
]
EOL
    echo -e "${GREEN}[OK]${NC} Default stations bestand aangemaakt"
fi

# Activeer venv en importeer de default stations
echo -e "${YELLOW}[FIX]${NC} Importeren van default stations..."
cd "$INSTALL_DIR"
source venv/bin/activate
python3 - << EOL
import os
import sys
import json
import logging
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from datetime import datetime

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

try:
    # Probeer .env bestand te laden
    from dotenv import load_dotenv
    load_dotenv('/opt/radiologger/.env')
except ImportError:
    logger.warning("Python-dotenv niet geïnstalleerd, gebruik eventueel aanwezige environment variabelen")

# Gebruik de DATABASE_URL uit de environment
database_url = os.environ.get('DATABASE_URL')
if not database_url:
    logger.error("Geen DATABASE_URL gevonden in environment")
    sys.exit(1)

# Definieer de database
Base = declarative_base()

# Definieer het Station model
class Station(Base):
    __tablename__ = 'station'
    
    id = Column(Integer, primary_key=True)
    name = Column(String(100), unique=True, nullable=False)
    recording_url = Column(String(255), nullable=False)
    always_on = Column(Boolean, default=False)
    schedule_start_date = Column(DateTime, nullable=True)
    schedule_start_hour = Column(Integer, nullable=True)
    schedule_end_date = Column(DateTime, nullable=True)
    schedule_end_hour = Column(Integer, nullable=True)
    record_reason = Column(String(255), nullable=True)
    display_order = Column(Integer, default=999)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    def __repr__(self):
        return f"<Station {self.name}>"

# Connect met de database
engine = create_engine(database_url)
Session = sessionmaker(bind=engine)
session = Session()

# Laad de default stations
try:
    with open('${DEFAULT_STATIONS_FILE}', 'r') as f:
        stations_data = json.load(f)
    
    # Controleer of er al stations bestaan
    existing_stations = session.query(Station).count()
    if existing_stations > 0:
        logger.info(f"Er zijn al {existing_stations} stations in de database, vraag bevestiging...")
        confirm = input("Er zijn al stations in de database. Wil je toch de default stations importeren? (j/n): ")
        if confirm.lower() != 'j':
            logger.info("Import geannuleerd door gebruiker")
            sys.exit(0)
    
    # Voeg de stations toe
    stations_added = 0
    for station_data in stations_data:
        # Controleer of het station al bestaat
        existing = session.query(Station).filter_by(name=station_data.get('name')).first()
        if existing:
            logger.info(f"Station '{station_data.get('name')}' bestaat al")
            continue
            
        # Voeg nieuw station toe
        station = Station(
            name=station_data.get('name'),
            recording_url=station_data.get('recording_url'),
            always_on=station_data.get('always_on', False)
        )
        session.add(station)
        stations_added += 1
    
    # Commit de changes
    session.commit()
    logger.info(f"✅ {stations_added} stations toegevoegd aan de database")
    
except Exception as e:
    logger.error(f"❌ Fout bij importeren van stations: {str(e)}")
    session.rollback()
    sys.exit(1)
finally:
    session.close()
EOL

deactivate

echo -e "\n${GREEN}[DONE]${NC} Standaard stations setup voltooid!"
echo -e "${YELLOW}[INFO]${NC} Je kunt nu inloggen in de Radiologger web interface om de stations te beheren."

exit 0