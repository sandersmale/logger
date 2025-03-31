#!/usr/bin/env python3
"""
Radiologger database initialisatie script
Dit script gebruikt de NeonDB die in .env staat
"""
import os
import sys
import logging
from datetime import datetime

# Configureer logging
logging.basicConfig(level=logging.INFO, 
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger('db_setup')

logger.info("Database initialisatie start")

try:
    # Import directe database modules
    try:
        import psycopg2
        from psycopg2 import sql
        logger.info("psycopg2 module succesvol geladen")
    except ImportError:
        logger.info("psycopg2 niet gevonden, proberen te installeren...")
        import subprocess
        try:
            # Eerst proberen met --break-system-packages voor Ubuntu 24.04+
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", 
                "--break-system-packages", "psycopg2-binary"
            ])
        except subprocess.CalledProcessError:
            # Fallback naar oudere methode
            logger.info("Installatie met --break-system-packages niet gelukt, fallback methode proberen...")
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", "psycopg2-binary"
            ])
        
        import psycopg2
        from psycopg2 import sql
        logger.info("psycopg2 succesvol geïnstalleerd")

    # Lees de database URL uit de .env
    env_path = '.env'
    db_url = None
    
    if os.path.exists(env_path):
        logger.info(f".env bestand gevonden: {env_path}")
        with open(env_path, 'r') as f:
            for line in f:
                if line.startswith('DATABASE_URL='):
                    db_url = line.split('=', 1)[1].strip().strip('"\'')
                    # Verberg wachtwoord in logs
                    sanitized_url = db_url.replace(db_url.split('@')[0].split(':', 1)[1], '****')
                    logger.info(f"Database URL gevonden: {sanitized_url}")
                    break
    
    if not db_url:
        logger.error("Geen DATABASE_URL gevonden in .env")
        sys.exit(1)

    # Controleer of we kunnen verbinden
    logger.info("Verbinding maken met database...")
    conn = psycopg2.connect(db_url)
    conn.autocommit = True
    cursor = conn.cursor()
    
    # Controleer de bestaande tabellen
    logger.info("Bestaande tabellen controleren...")
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
    """)
    tables = cursor.fetchall()
    table_names = [table[0] for table in tables]
    
    logger.info(f"Gevonden tabellen: {', '.join(table_names)}")
    
    # Controleer of de belangrijkste tabellen bestaan
    required_tables = ['user', 'station', 'recording', 'scheduled_job', 'dennis_station']
    missing_tables = [table for table in required_tables if table not in table_names]
    
    if missing_tables:
        logger.warning(f"De volgende tabellen ontbreken: {', '.join(missing_tables)}")
        logger.info("Tabellen aanmaken...")
        
        # SQL voor het aanmaken van tabellen die ontbreken
        if 'user' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "user" (
                    id SERIAL PRIMARY KEY,
                    username VARCHAR(64) UNIQUE NOT NULL,
                    password_hash VARCHAR(256) NOT NULL,
                    role VARCHAR(20) DEFAULT 'listener' NOT NULL,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'user' aangemaakt")
        
        if 'station' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "station" (
                    id SERIAL PRIMARY KEY,
                    name VARCHAR(100) UNIQUE NOT NULL,
                    recording_url VARCHAR(255) NOT NULL,
                    always_on BOOLEAN DEFAULT FALSE,
                    display_order INTEGER DEFAULT 999,
                    schedule_start_date DATE,
                    schedule_start_hour INTEGER,
                    schedule_end_date DATE,
                    schedule_end_hour INTEGER,
                    record_reason VARCHAR(255),
                    created_at TIMESTAMP DEFAULT NOW(),
                    updated_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'station' aangemaakt")
        
        if 'dennis_station' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "dennis_station" (
                    id SERIAL PRIMARY KEY,
                    folder VARCHAR(100) NOT NULL,
                    name VARCHAR(100) NOT NULL,
                    url VARCHAR(255) NOT NULL,
                    visible_in_logger BOOLEAN DEFAULT FALSE,
                    last_updated TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'dennis_station' aangemaakt")
        
        if 'recording' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "recording" (
                    id SERIAL PRIMARY KEY,
                    station_id INTEGER REFERENCES "station"(id) NOT NULL,
                    date DATE NOT NULL,
                    hour VARCHAR(2) NOT NULL,
                    filepath VARCHAR(255) NOT NULL,
                    program_title VARCHAR(255),
                    recording_type VARCHAR(20) DEFAULT 'scheduled',
                    s3_uploaded BOOLEAN DEFAULT FALSE,
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'recording' aangemaakt")
        
        if 'scheduled_job' not in table_names:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS "scheduled_job" (
                    id SERIAL PRIMARY KEY,
                    job_id VARCHAR(100) NOT NULL,
                    station_id INTEGER REFERENCES "station"(id) NOT NULL,
                    job_type VARCHAR(20) NOT NULL,
                    start_time TIMESTAMP NOT NULL,
                    end_time TIMESTAMP,
                    status VARCHAR(20) DEFAULT 'scheduled',
                    created_at TIMESTAMP DEFAULT NOW()
                )
            """)
            logger.info("Tabel 'scheduled_job' aangemaakt")
    else:
        logger.info("Alle vereiste tabellen zijn aanwezig!")
    
    # Controleer of er gebruikers bestaan
    try:
        cursor.execute("SELECT COUNT(*) FROM \"user\"")
        result = cursor.fetchone()
        user_count = result[0] if result else 0
        logger.info(f"User count query succesvol uitgevoerd: {user_count}")
    except Exception as e:
        logger.warning(f"Fout bij ophalen user count: {str(e)}")
        user_count = 0  # Veilige fallback
    
    if user_count == 0:
        logger.info("Geen gebruikers gevonden. Gebruikers worden aangemaakt via de setup pagina bij eerste bezoek.")
    else:
        logger.info(f"Er zijn al {user_count} gebruikers in de database")
    
    # Controleer of er stations bestaan
    try:
        cursor.execute("SELECT COUNT(*) FROM station")
        result = cursor.fetchone()
        station_count = result[0] if result else 0
        logger.info(f"Station count query succesvol uitgevoerd: {station_count}")
    except Exception as e:
        logger.warning(f"Fout bij ophalen station count: {str(e)}")
        station_count = 0  # Veilige fallback
    
    if station_count == 0:
        logger.info("Geen stations gevonden, demo stations aanmaken...")
        
        # Voeg enkele demo stations toe
        cursor.execute("""
            INSERT INTO "station" (name, recording_url, always_on, display_order)
            VALUES (%s, %s, %s, %s)
        """, ("NPO Radio 1", "https://icecast.omroep.nl/radio1-bb-mp3", True, 1))
        
        cursor.execute("""
            INSERT INTO "station" (name, recording_url, always_on, display_order)
            VALUES (%s, %s, %s, %s)
        """, ("NPO Radio 2", "https://icecast.omroep.nl/radio2-bb-mp3", True, 2))
        
        cursor.execute("""
            INSERT INTO "station" (name, recording_url, always_on, display_order)
            VALUES (%s, %s, %s, %s)
        """, ("NPO 3FM", "https://icecast.omroep.nl/3fm-bb-mp3", False, 3))
        
        logger.info("Demo stations aangemaakt")
    else:
        logger.info(f"Er zijn al {station_count} stations in de database")
    
    cursor.close()
    conn.close()
    
    logger.info("✅ Database initialisatie succesvol afgerond!")
    sys.exit(0)

except Exception as e:
    logger.error(f"❌ Fout bij database initialisatie: {str(e)}")
    import traceback
    logger.error(traceback.format_exc())
    sys.exit(1)