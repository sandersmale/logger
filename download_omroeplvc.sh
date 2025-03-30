#!/usr/bin/env bash
#
# download_omroeplvc.sh - Download het 'gemist' opnamebestand van Omroep Land van Cuijk
#
# Dit script gaat ervan uit dat het 8 minuten na ieder uur wordt uitgevoerd (bijv. via cron).
# Het bepaalt op basis van de huidige tijd (of de vorige uur als de minuut < 8 is)
# de juiste URL. De URL wordt opgebouwd als:
#   https://gemist.omroeplvc.nl/{dagabbreviation}{HH}.mp3
# waarbij {dagabbreviation} de Nederlandse afkorting is (ma, di, wo, do, vr, za, zo)
# en HH het uur in twee cijfers.
#
# Het bestand wordt opgeslagen in:
#   /var/lib/radiologger/recordings/omroep land van cuijk/<YYYY-MM-DD>/<HH>.mp3
#
# Logging vindt plaats in /var/log/radiologger/download_omroeplvc.log
#

set -euo pipefail

# Configuratie - gebaseerd op radiologger configuratie
# Als script via .env geladen wordt, gebruik dan de environment variabelen
# Anders gebruik standaard paden
LOG_DIR="${LOGS_DIR:-/var/log/radiologger}"
RECORDINGS_DIR="${RECORDINGS_DIR:-/var/lib/radiologger/recordings}"
LOG_FILE="${LOG_DIR}/download_omroeplvc.log"
LOCAL_BASE="${RECORDINGS_DIR}/omroep land van cuijk"
REMOTE_URL_BASE="${OMROEP_LVC_URL:-https://gemist.omroeplvc.nl}"

# Zorg dat de directories bestaan
mkdir -p "$LOG_DIR"
mkdir -p "$LOCAL_BASE"

# Functie voor logging (schrijft zowel naar STDOUT als naar het logbestand)
log() {
    echo "$(date +'%F %T') - $1" | tee -a "$LOG_FILE"
}

log "Script gestart."

# Bepaal de tijd waarop we de opname moeten downloaden.
# We gaan ervan uit dat het script 8 minuten na ieder uur draait.
# We downloaden altijd het vorige uur om ervoor te zorgen dat de
# opname volledig beschikbaar is in het archief.
current_hour=$(date -d "1 hour ago" +%H)
current_date=$(date -d "1 hour ago" +%F)
current_minute=$(date +%M)

if [ "$current_minute" -lt 8 ] || [ "$current_minute" -gt 15 ]; then
    log "⚠️ Let op: Script wordt niet op de optimale tijd uitgevoerd (huidige minuut: $current_minute, ideaal: 8-15). We gaan toch door."
fi

# Bepaal de dag van de week als nummer (1=Maandag, ... 7=Zondag)
day_number=$(date -d "1 hour ago" +%u)
case $day_number in
    1) day_abbr="ma" ;;
    2) day_abbr="di" ;;
    3) day_abbr="wo" ;;
    4) day_abbr="do" ;;
    5) day_abbr="vr" ;;
    6) day_abbr="za" ;;
    7) day_abbr="zo" ;;
    *) day_abbr="unknown" ;;
esac

if [ "$day_abbr" == "unknown" ]; then
    log "Onbekende dagnummer: $day_number. Stoppen."
    exit 1
fi

# Bouw de URL. Bijvoorbeeld: voor maandag 06:00 wordt dit "https://gemist.omroeplvc.nl/ma06.mp3"
file_name="${day_abbr}${current_hour}.mp3"
remote_file_url="${REMOTE_URL_BASE}/${file_name}"

log "Probeer bestand te downloaden van: $remote_file_url"

# Bepaal de lokale directory en het bestandsnaam
local_dir="${LOCAL_BASE}/${current_date}"
mkdir -p "$local_dir"
local_file="${local_dir}/${current_hour}.mp3"

log "Opslaan naar: $local_file"

# Download het bestand met curl. Gebruik -f (fail) en -L (volg redirects)
if curl -f -L "$remote_file_url" -o "$local_file"; then
    log "Download succesvol: $local_file"
else
    log "ERROR: Download mislukt voor $remote_file_url"
    exit 1
fi

# Controleer of het gedownloade bestand geldig is.
# Indien het bestand HTML bevat (bijv. een redirect naar de homepage), verwijderen we het.
if grep -qi "<html" "$local_file"; then
    log "Gedownload bestand bevat HTML (vermoedelijk niet beschikbaar). Bestand wordt verwijderd."
    rm -f "$local_file"
    exit 0
fi

log "Script voltooid."
exit 0