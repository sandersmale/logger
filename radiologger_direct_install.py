#!/usr/bin/env python3
"""
Radiologger direct installatiescript
Dit script initialiseert de database en maakt de basis gebruikers aan
zonder afhankelijk te zijn van bestaande modules of imports.

Het script toont gedetailleerde debugging informatie en vereist geen
externe dependencies of ingewikkelde imports.
"""
import os
import sys
import importlib.util
import sqlite3
import subprocess
import psycopg2
import traceback
from datetime import datetime
from pathlib import Path


# Configuratie
INSTALL_DIR = "/opt/radiologger"
LOG_FILE = "/tmp/radiologger_direct_install.log"
DB_URL = None  # Wordt later opgezocht in .env
ADMIN_PW = "radioadmin"
EDITOR_PW = "radioeditor"
LISTENER_PW = "radioluisteraar"


def log(message, show=True):
    """Log een bericht naar het logbestand en toon het eventueel op het scherm"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    log_message = f"{timestamp} - {message}"
    
    # Zorg ervoor dat het logbestand bestaat
    if not os.path.exists(os.path.dirname(LOG_FILE)):
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    
    with open(LOG_FILE, "a") as f:
        f.write(log_message + "\n")
    
    if show:
        print(message)


def get_python_info():
    """Verzamel informatie over de Python-omgeving"""
    log("Python informatie:", show=True)
    log(f"Python versie: {sys.version}", show=True)
    log(f"Python executable: {sys.executable}", show=True)
    log(f"sys.path: {sys.path}", show=True)
    
    # Controleer of belangrijke modules beschikbaar zijn
    for module in ["flask", "sqlalchemy", "psycopg2", "werkzeug"]:
        try:
            importlib.import_module(module)
            log(f"✅ Module {module} is beschikbaar")
        except ImportError:
            log(f"❌ Module {module} is NIET beschikbaar")
    
    # Probeer flask met een direct importpad
    try:
        flask_path = importlib.util.find_spec("flask")
        log(f"Flask pad: {flask_path.origin if flask_path else 'Niet gevonden'}")
    except ImportError:
        log("❌ Flask kan niet gevonden worden via importlib")


def locate_app_file():
    """Zoek het app.py bestand"""
    app_path = os.path.join(INSTALL_DIR, "app.py")
    
    if os.path.exists(app_path):
        log(f"✅ app.py gevonden op: {app_path}")
        with open(app_path, "r") as f:
            content = f.read()
            log(f"Inhoud van app.py (eerste 300 karakters):\n{content[:300]}...")
        return app_path
    else:
        log(f"❌ app.py NIET gevonden op: {app_path}")
        
        # Zoek in subdirectories
        for root, dirs, files in os.walk(INSTALL_DIR):
            if "app.py" in files:
                found_path = os.path.join(root, "app.py")
                log(f"✅ app.py gevonden op alternatieve locatie: {found_path}")
                return found_path
        
        log("❌ app.py nergens gevonden")
        return None


def read_env_file():
    """Lees het .env bestand om de database configuratie te verkrijgen"""
    global DB_URL
    env_path = os.path.join(INSTALL_DIR, ".env")
    
    if os.path.exists(env_path):
        log(f"✅ .env bestand gevonden op: {env_path}")
        with open(env_path, "r") as f:
            content = f.read()
            for line in content.splitlines():
                if line.startswith("DATABASE_URL="):
                    DB_URL = line.split("=", 1)[1].strip().strip('"\'')
                    log(f"✅ DATABASE_URL gevonden: {DB_URL}")
    else:
        log(f"❌ .env bestand NIET gevonden op: {env_path}")


def setup_database_direct():
    """Maak de database tabellen direct aan met SQL-commando's in plaats van ORM"""
    if not DB_URL:
        log("❌ Geen DATABASE_URL gevonden, database initialisatie overgeslagen")
        return False
    
    log("🔄 Start directe database-initialisatie met SQL...")
    
    try:
        # Verbind met de PostgreSQL database
        conn = psycopg2.connect(DB_URL)
        conn.autocommit = True
        cursor = conn.cursor()
        
        log("✅ Verbinding met database gemaakt")
        
        # Maak de user tabel aan
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS "user" (
                id SERIAL PRIMARY KEY,
                username VARCHAR(64) UNIQUE NOT NULL,
                password_hash VARCHAR(256) NOT NULL,
                role VARCHAR(20) DEFAULT 'listener' NOT NULL,
                created_at TIMESTAMP DEFAULT NOW()
            )
        """)
        
        # Maak de station tabel aan
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
        
        # Maak de dennis_station tabel aan
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
        
        # Maak de recording tabel aan
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
        
        # Maak de scheduled_job tabel aan
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
        
        log("✅ Database tabellen succesvol aangemaakt")
        
        # Controleer of er al gebruikers zijn
        cursor.execute("SELECT COUNT(*) FROM \"user\"")
        user_count = cursor.fetchone()[0]
        
        if user_count == 0:
            log("🔄 Geen gebruikers gevonden, standaard gebruikers aanmaken...")
            
            # Werkzeug generate_password_hash functie nabootsen (zeer eenvoudige implementatie)
            # In een productieomgeving zou je werkzeug moeten gebruiken voor betere beveiliging
            def simple_hash(password):
                import hashlib
                # Een zeer eenvoudige hash functie, ALLEEN voor dit voorbeeld
                return "pbkdf2:sha256:150000$" + hashlib.sha256(password.encode()).hexdigest()
            
            # Maak de standaard gebruikers aan
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("admin", simple_hash(ADMIN_PW), "admin"))
            
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("editor", simple_hash(EDITOR_PW), "editor"))
            
            cursor.execute("""
                INSERT INTO "user" (username, password_hash, role)
                VALUES (%s, %s, %s)
            """, ("luisteraar", simple_hash(LISTENER_PW), "listener"))
            
            log("✅ Standaard gebruikers aangemaakt")
        else:
            log(f"ℹ️ Er zijn al {user_count} gebruikers in de database, geen nieuwe gebruikers aangemaakt")
        
        conn.close()
        return True
        
    except Exception as e:
        log(f"❌ Fout bij directe database-initialisatie: {e}")
        log(traceback.format_exc())
        return False


def main():
    """Hoofdfunctie die het script uitvoert"""
    log("=" * 60)
    log("Radiologger Direct Installatie Script")
    log("=" * 60)
    log(f"Logbestand: {LOG_FILE}")
    
    # Controleer of de installatiemap bestaat
    if not os.path.exists(INSTALL_DIR):
        log(f"❌ Installatiemap '{INSTALL_DIR}' bestaat niet")
        return False
    
    # Wijzig naar de installatiedirectory
    os.chdir(INSTALL_DIR)
    log(f"✅ Huidige werkdirectory: {os.getcwd()}")
    
    # Verzamel Python informatie
    get_python_info()
    
    # Zoek app.py
    app_file = locate_app_file()
    
    # Lees de database configuratie
    read_env_file()
    
    # Initialiseer de database
    db_success = setup_database_direct()
    
    if db_success:
        log("✅ Database installatie voltooid!")
    else:
        log("❌ Database installatie MISLUKT!")
    
    log("=" * 60)
    log(f"Installatie voltooid. Bekijk het logbestand voor details: {LOG_FILE}")
    log("=" * 60)
    
    return db_success


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)