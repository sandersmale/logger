import os
from app import app, db
from models import User, Station, DennisStation, Recording, ScheduledJob
from werkzeug.security import generate_password_hash
from datetime import datetime, timedelta
from default_stations import default_stations
import json

def reset_stations():
    """
    Reset en herbevolken van stations naar de default_stations.json
    Verwijdert eerst alle bestaande stations en gerelateerde data.
    """
    with app.app_context():
        print("Resetten van stations...")
        
        # Verwijder eerst alle scheduled jobs
        print("Verwijderen van bestaande scheduled jobs...")
        ScheduledJob.query.delete()
        
        # Verwijder dan alle opnames
        print("Verwijderen van bestaande opnames...")
        Recording.query.delete()
        
        # Verwijder tenslotte alle stations
        print("Verwijderen van bestaande stations...")
        Station.query.delete()
        
        # Commit de delete operaties
        db.session.commit()
        
        print("Toevoegen van nieuwe stations uit default_stations.json...")
        
        # Laad de standaard stations uit default_stations.json
        try:
            with open('default_stations.json', 'r') as f:
                default_stations_data = json.load(f)
            
            # Voeg de stations toe
            for idx, station in enumerate(default_stations_data):
                print(f"Toevoegen station: {station['name']}")
                new_station = Station(
                    name=station['name'],
                    recording_url=station['recording_url'],
                    always_on=bool(station['always_on']),
                    display_order=idx * 10  # 0, 10, 20, etc.
                )
                
                # Voeg planning toe indien aanwezig
                if station.get('schedule_start_date') and station.get('schedule_start_hour') and \
                   station.get('schedule_end_date') and station.get('schedule_end_hour'):
                    new_station.schedule_start_date = datetime.strptime(station['schedule_start_date'], '%Y-%m-%d').date() \
                                                if isinstance(station['schedule_start_date'], str) else station['schedule_start_date']
                    new_station.schedule_start_hour = station['schedule_start_hour']
                    new_station.schedule_end_date = datetime.strptime(station['schedule_end_date'], '%Y-%m-%d').date() \
                                                if isinstance(station['schedule_end_date'], str) else station['schedule_end_date']
                    new_station.schedule_end_hour = station['schedule_end_hour']
                    new_station.record_reason = station.get('record_reason', 'Geplande opname')
                
                db.session.add(new_station)
            
            # Commit de add operaties
            db.session.commit()
            print(f"✅ {len(default_stations_data)} stations succesvol toegevoegd!")
            
        except Exception as e:
            print(f"❌ Fout bij toevoegen van stations: {e}")
            db.session.rollback()
            raise

if __name__ == '__main__':
    try:
        reset_stations()
    except Exception as e:
        print(f"Fatal error: {e}")