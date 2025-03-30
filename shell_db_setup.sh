#!/bin/bash
# shell_db_setup.sh
# Een volledig standalone shell script voor het opzetten van de database
# zonder enige afhankelijkheid van Python of imports
#
# Dit script maakt direct de database aan met pure SQL via het psql commando
# Het enige dat vereist is, is toegang tot een PostgreSQL installatie

# Configuratie uit omgevingsvariabelen of defaultwaarden
DB_USER=${DATABASE_USER:-"radiologger"}
DB_PASSWORD=${DATABASE_PASSWORD:-"radiologgerpass"}
DB_NAME=${DATABASE_NAME:-"radiologger"}
DB_HOST=${DATABASE_HOST:-"localhost"}
DB_PORT=${DATABASE_PORT:-"5432"}

# Log bestand voor debug informatie
LOG_FILE="/tmp/shell_db_setup.log"

# Logging functie
log_message() {
  local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Maak een nieuw logbestand aan
echo "Shell Database Setup Log - $(date)" > "$LOG_FILE"
echo "-------------------------------------" >> "$LOG_FILE"

log_message "Shell database setup script gestart"
log_message "Gebruikt postgresql://$DB_USER:******@$DB_HOST:$DB_PORT/$DB_NAME"

# Controleer of psql beschikbaar is
if ! command -v psql &> /dev/null; then
  log_message "❌ FOUT: psql commando niet gevonden. Installeer PostgreSQL client."
  exit 1
fi

# Genereer het SQL script
TMP_SQL_FILE=$(mktemp)
chmod 600 "$TMP_SQL_FILE"

cat > "$TMP_SQL_FILE" << 'EOF'
-- Maak de user tabel aan
CREATE TABLE IF NOT EXISTS "user" (
    id SERIAL PRIMARY KEY,
    username VARCHAR(64) UNIQUE NOT NULL,
    password_hash VARCHAR(256) NOT NULL,
    role VARCHAR(20) DEFAULT 'listener' NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Maak de station tabel aan
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
);

-- Maak de dennis_station tabel aan
CREATE TABLE IF NOT EXISTS "dennis_station" (
    id SERIAL PRIMARY KEY,
    folder VARCHAR(100) NOT NULL,
    name VARCHAR(100) NOT NULL,
    url VARCHAR(255) NOT NULL,
    visible_in_logger BOOLEAN DEFAULT FALSE,
    last_updated TIMESTAMP DEFAULT NOW()
);

-- Maak de recording tabel aan
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
);

-- Maak de scheduled_job tabel aan
CREATE TABLE IF NOT EXISTS "scheduled_job" (
    id SERIAL PRIMARY KEY,
    job_id VARCHAR(100) NOT NULL,
    station_id INTEGER REFERENCES "station"(id) NOT NULL,
    job_type VARCHAR(20) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    status VARCHAR(20) DEFAULT 'scheduled',
    created_at TIMESTAMP DEFAULT NOW()
);

-- Controleer of er al gebruikers zijn
DO $$
DECLARE
    user_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO user_count FROM "user";
    
    IF user_count = 0 THEN
        -- Maak standaard admin gebruiker (wachtwoord: radioadmin)
        INSERT INTO "user" (username, password_hash, role)
        VALUES ('admin', 'pbkdf2:sha256:150000$8e7e812c0e87d1b9e27efaca3f63ce84cfddfbe10be3a1de9c9a3f2c22ff9e91', 'admin');
        
        -- Maak standaard editor gebruiker (wachtwoord: radioeditor)
        INSERT INTO "user" (username, password_hash, role)
        VALUES ('editor', 'pbkdf2:sha256:150000$bc88b347fba0cb8eeeb35050a45794a41c71fcb56e2e5ef0f26c71213000f89a', 'editor');
        
        -- Maak standaard luisteraar gebruiker (wachtwoord: radioluisteraar)
        INSERT INTO "user" (username, password_hash, role)
        VALUES ('luisteraar', 'pbkdf2:sha256:150000$66d6f30f0bef2c6b9622c93aa6906bbe5b3c5a87e0ef3acb5e9f55b468c83e90', 'listener');
    END IF;
END $$;

-- Voeg demo stations toe als er nog geen stations zijn
DO $$
DECLARE
    station_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO station_count FROM "station";
    
    IF station_count = 0 THEN
        -- Voeg enkele demo stations toe
        INSERT INTO "station" (name, recording_url, always_on, display_order)
        VALUES ('NPO Radio 1', 'https://icecast.omroep.nl/radio1-bb-mp3', true, 1);
        
        INSERT INTO "station" (name, recording_url, always_on, display_order)
        VALUES ('NPO Radio 2', 'https://icecast.omroep.nl/radio2-bb-mp3', true, 2);
        
        INSERT INTO "station" (name, recording_url, always_on, display_order)
        VALUES ('NPO 3FM', 'https://icecast.omroep.nl/3fm-bb-mp3', false, 3);
    END IF;
END $$;
EOF

# Voer het SQL script uit
export PGPASSWORD="$DB_PASSWORD"
log_message "🔄 Database tabellen en basisgegevens aanmaken..."

if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$TMP_SQL_FILE" >> "$LOG_FILE" 2>&1; then
  log_message "✅ Database tabellen en basisgegevens succesvol aangemaakt!"
  success=true
else
  log_message "❌ Fout bij aanmaken database tabellen. Controleer $LOG_FILE voor details."
  
  # Probeer als alternatief met postgres gebruiker als we root zijn
  if [ "$(id -u)" -eq 0 ]; then
    log_message "🔄 Proberen als postgres gebruiker..."
    if sudo -u postgres psql -d "$DB_NAME" -f "$TMP_SQL_FILE" >> "$LOG_FILE" 2>&1; then
      log_message "✅ Database tabellen en basisgegevens succesvol aangemaakt met postgres gebruiker!"
      success=true
    else
      log_message "❌ Ook mislukt met postgres gebruiker. Zie $LOG_FILE voor details."
      success=false
    fi
  else
    success=false
  fi
fi

# Ruim het tijdelijke bestand op
rm -f "$TMP_SQL_FILE"

if [ "$success" = true ]; then
  log_message "✅ Database setup succesvol voltooid!"
  exit 0
else
  log_message "❌ Database setup mislukt. Controleer het logbestand: $LOG_FILE"
  cat "$LOG_FILE"
  exit 1
fi