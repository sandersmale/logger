import os
import sqlite3
import json
from datetime import datetime, date

def extract_stations_from_old_db(db_path):
    """
    Extract stations from old SQLite database and return them as a list of dictionaries.
    """
    try:
        # Connect to the database
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        # Check if the stations table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='stations'")
        if not cursor.fetchone():
            print(f"No 'stations' table found in {db_path}")
            conn.close()
            return []
        
        # Query all stations
        cursor.execute("SELECT * FROM stations")
        stations = []
        
        for row in cursor.fetchall():
            # Convert Row object to dict
            station = dict(row)
            stations.append(station)
        
        conn.close()
        return stations
    
    except sqlite3.Error as e:
        print(f"SQLite error: {e}")
        return []
    except Exception as e:
        print(f"Error: {e}")
        return []

def save_stations_to_json(stations, output_path="default_stations.json"):
    """
    Save stations to a JSON file.
    """
    # Convert any non-serializable objects to strings
    for station in stations:
        for key, value in station.items():
            if isinstance(value, (datetime, date)):
                station[key] = value.isoformat()
    
    try:
        with open(output_path, 'w') as f:
            json.dump(stations, f, indent=4)
        print(f"Saved {len(stations)} stations to {output_path}")
        return True
    except Exception as e:
        print(f"Error saving to JSON: {e}")
        return False

if __name__ == "__main__":
    db_path = "attached_assets/radiologger.db"
    
    if not os.path.exists(db_path):
        print(f"Database file not found: {db_path}")
    else:
        stations = extract_stations_from_old_db(db_path)
        if stations:
            save_stations_to_json(stations)