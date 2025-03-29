#!/usr/bin/env bash
#
# upload_and_remove.sh - Automatisch uploaden naar Wasabi + DB-synchronisatie + opruimen.
#
# Dit script uploadt nieuwe MP3-opnames naar Wasabi, synchroniseert de SQLite-database
# met de remote bestanden en verwijdert vervolgens alle lokale bestanden ouder dan 60 minuten.
#
# Gebruiksinstructies:
#  - Zorg dat rclone correct is geconfigureerd met een remote genaamd 'wasabi'.
#  - Zet dit script in je crontab of voer het handmatig uit.
#  - Pas paden, database-locatie en remote pad aan indien nodig.
#

########################################################################
# 1. Instellingen en strict mode
########################################################################
set -o pipefail
set -u

LOCAL_BASE="/var/private/opnames"         # Lokale map met opnames
REMOTE_BASE="wasabi:radiologger/opnames"    # Wasabi remote pad
DB_PATH="/var/private/db/radiologger.db"    # Pad naar de SQLite database
LOG_DIR="/var/private/logs"
LOG_MAIN="$LOG_DIR/upload_and_remove.log"

# Zorg dat de log-directory bestaat
mkdir -p "$LOG_DIR"

# Schrijf alle stdout/stderr naar het hoofdlog
echo "$(date +'%F %T') - Script started." >> "$LOG_MAIN"
exec >> "$LOG_MAIN" 2>&1

# Variabelen voor tijdelijke bestanden
tmp_remote=""
tmp_db=""
tmp_added=""
tmp_removed=""

########################################################################
# 2. Functies voor opruimen en foutafhandeling
########################################################################
cleanup() {
    rm -f "$tmp_remote" "$tmp_db" "$tmp_added" "$tmp_removed"
}
error_exit() {
    local lineno="$1"
    local exitcode="$2"
    echo "$(date +'%F %T') - ERROR: Stopped at line $lineno with exit code $exitcode." >> "$LOG_MAIN"
    exit "$exitcode"
}

trap 'cleanup' EXIT
trap 'error_exit $LINENO $?' ERR

# Maak tijdelijke bestanden
tmp_remote="$(mktemp)" || { echo "ERROR: mktemp failed."; exit 1; }
tmp_db="$(mktemp)" || { echo "ERROR: mktemp failed."; exit 1; }
tmp_added="$(mktemp)" || { echo "ERROR: mktemp failed."; exit 1; }
tmp_removed="$(mktemp)" || { echo "ERROR: mktemp failed."; exit 1; }

########################################################################
# 3. Upload nieuwe MP3-opnames
########################################################################
echo "$(date +'%F %T') - Scanning '$LOCAL_BASE' for new .mp3 files..."

# Zoek alleen mp3-bestanden die eindigen op HH.mp3 (uur tussen 00 en 23)
find "$LOCAL_BASE" -type f -regextype posix-extended -regex '.*(0[0-9]|1[0-9]|2[0-3])\.mp3$' -print0 |
while IFS= read -r -d '' file; do
  # Bepaal station: map 2 niveaus boven het bestand
  station="$(basename "$(dirname "$(dirname "$file")")")"

  # Als de 'station'-map letterlijk "opnames" heet, slaan we deze over
  if [[ "$station" == "opnames" ]]; then
    echo "$(date +'%F %T') - SKIP: Bestand $file zit in de hoofdmap 'opnames', overslaan."
    continue
  fi

  # date_dir = de map direct boven het bestand (bijv. '2025-02-26')
  date_dir="$(basename "$(dirname "$file")")"
  # hour_file = de bestandsnaam (bijv. '13.mp3')
  hour_file="$(basename "$file")"
  hour="${hour_file%.mp3}"

  dest_path="$REMOTE_BASE/$station/$date_dir/$hour_file"
  echo "$(date +'%F %T') - Uploading $file -> $dest_path"

  # Upload met rclone copyto (zorgt dat het doelbestand exact die naam krijgt)
  if ! rclone copyto "$file" "$dest_path"; then
    echo "$(date +'%F %T') - ERROR: rclone copyto failed for $file -> $dest_path"
  fi
done

########################################################################
# 4. Synchroniseer de SQLite-database met Wasabi
########################################################################
echo "$(date +'%F %T') - Listing files on Wasabi (remote)..."
if ! rclone lsf -R --files-only "$REMOTE_BASE" | sort > "$tmp_remote"; then
    echo "$(date +'%F %T') - ERROR: Could not list remote files from $REMOTE_BASE"
    exit 2
fi

echo "$(date +'%F %T') - Fetching current DB records..."
if ! sqlite3 "$DB_PATH" \
       "SELECT station || '/' || date || '/' || hour || '.mp3' FROM recordings;" \
       | sort > "$tmp_db"
then
    echo "$(date +'%F %T') - ERROR: DB query failed."
    exit 3
fi

# Bepaal welke paden in DB staan maar niet (meer) op Wasabi (te verwijderen)
comm -23 "$tmp_db" "$tmp_remote" > "$tmp_removed"
# Bepaal welke paden op Wasabi staan maar nog niet in DB (toe te voegen)
comm -13 "$tmp_db" "$tmp_remote" > "$tmp_added"

########################################################################
# 5. Verwijderen uit DB wat niet meer op Wasabi staat
########################################################################
echo "$(date +'%F %T') - Removing DB records not on Wasabi..."
while IFS= read -r removed_path; do
  [[ -z "$removed_path" ]] && continue
  station="$(cut -d'/' -f1 <<< "$removed_path")"
  date_dir="$(cut -d'/' -f2 <<< "$removed_path")"
  hour_file="$(cut -d'/' -f3 <<< "$removed_path")"
  hour="${hour_file%.mp3}"

  if sqlite3 "$DB_PATH" \
    "DELETE FROM recordings WHERE station='$station' AND date='$date_dir' AND hour='$hour';"
  then
    echo "$(date +'%F %T') - Removed $removed_path from DB"
  else
    echo "$(date +'%F %T') - ERROR: Failed to delete $removed_path from DB"
  fi
done < "$tmp_removed"

########################################################################
# 6. Toevoegen aan DB wat op Wasabi staat maar nog niet in DB
########################################################################
echo "$(date +'%F %T') - Adding new DB records for files on Wasabi..."
while IFS= read -r added_path; do
  [[ -z "$added_path" ]] && continue
  station="$(cut -d'/' -f1 <<< "$added_path")"
  date_dir="$(cut -d'/' -f2 <<< "$added_path")"
  hour_file="$(cut -d'/' -f3 <<< "$added_path")"
  hour="${hour_file%.mp3}"

  # De 'filepath' sla je op als: opnames/station/date/hour.mp3
  file_path="opnames/$station/$date_dir/$hour_file"

  if sqlite3 "$DB_PATH" \
    "INSERT INTO recordings (station, date, hour, filepath, program_title)
     VALUES ('$station','$date_dir','$hour','$file_path','');"
  then
    echo "$(date +'%F %T') - Added $added_path (DB record: $file_path)"
  else
    echo "$(date +'%F %T') - ERROR: Failed to add $added_path to DB"
  fi
done < "$tmp_added"

########################################################################
# 7. Verwijder lokale bestanden ouder dan 60 minuten
########################################################################
echo "$(date +'%F %T') - Removing local files older than 60 minutes..."
find "$LOCAL_BASE" -type f -mmin +60 -name '*.mp3' -print -delete

echo "$(date +'%F %T') - Script finished."
exit 0
