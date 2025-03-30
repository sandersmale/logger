import os
from app import app, db
from models import User, Station, DennisStation
from werkzeug.security import generate_password_hash
from datetime import datetime, timedelta
from default_stations import default_stations

def seed_initial_data(use_default_stations=False):
    """
    Seed initial data in the database.
    Only runs when the database is empty.
    
    Args:
        use_default_stations (bool): If True, use the stations imported from old DB
    """
    with app.app_context():
        # Check if we already have users
        if User.query.count() > 0:
            print("Database already contains data, skipping seeding")
            return
        
        print("Seeding initial data...")
        
        # Create admin user
        admin_user = User(
            username='admin',
            password_hash=generate_password_hash('radioadmin'),
            role='admin'
        )
        
        editor_user = User(
            username='editor',
            password_hash=generate_password_hash('radioeditor'),
            role='editor'
        )
        
        listener_user = User(
            username='luisteraar',
            password_hash=generate_password_hash('radioluisteraar'),
            role='listener'
        )
        
        db.session.add(admin_user)
        db.session.add(editor_user)
        db.session.add(listener_user)
        
        # Determine which stations to use
        if use_default_stations:
            # Use stations imported from old DB
            stations_to_use = default_stations
            print("Using imported stations from old DB...")
        else:
            # Use example stations
            stations_to_use = [
                {
                    'name': 'NPO Radio 1',
                    'recording_url': 'https://icecast.omroep.nl/radio1-bb-mp3',
                    'always_on': True,
                    'display_order': 10
                },
                {
                    'name': 'NPO Radio 2',
                    'recording_url': 'https://icecast.omroep.nl/radio2-bb-mp3',
                    'always_on': False,
                    'display_order': 20,
                    'schedule': {
                        'start_date': datetime.now().date(),
                        'start_hour': 8,
                        'end_date': (datetime.now() + timedelta(days=7)).date(),
                        'end_hour': 18,
                        'reason': 'Top 2000'
                    }
                },
                {
                    'name': 'NPO 3FM',
                    'recording_url': 'https://icecast.omroep.nl/3fm-bb-mp3',
                    'always_on': False,
                    'display_order': 30
                },
                {
                    'name': 'NPO Radio 4',
                    'recording_url': 'https://icecast.omroep.nl/radio4-bb-mp3',
                    'always_on': False,
                    'display_order': 40
                },
                {
                    'name': 'NPO Radio 5',
                    'recording_url': 'https://icecast.omroep.nl/radio5-bb-mp3',
                    'always_on': False,
                    'display_order': 50
                },
                {
                    'name': 'omroep land van cuijk',
                    'recording_url': 'https://stream.omroeplvc.nl:8443/stream',
                    'always_on': False,
                    'display_order': 60
                }
            ]
            print("Using default example stations...")
        
        # Add the selected stations to the database
        for station_data in stations_to_use:
            station = Station(
                name=station_data['name'],
                recording_url=station_data['recording_url'],
                always_on=station_data['always_on'],
                display_order=station_data.get('display_order', 999)
            )
            
            if 'schedule' in station_data:
                station.schedule_start_date = station_data['schedule']['start_date']
                station.schedule_start_hour = station_data['schedule']['start_hour']
                station.schedule_end_date = station_data['schedule']['end_date']
                station.schedule_end_hour = station_data['schedule']['end_hour']
                station.record_reason = station_data['schedule']['reason']
            
            db.session.add(station)
        
        # Dennis stations worden niet vooraf gevuld
        # Deze worden alleen bijgewerkt wanneer de gebruiker expliciet 
        # de API vernieuwt via de refresh functie
        print("Dennis stations worden niet voorgevuld, deze worden opgehaald via de API refresh actie")
        
        db.session.commit()
        print("Initial data seeded successfully!")

if __name__ == '__main__':
    import sys
    use_default = False
    if len(sys.argv) > 1 and sys.argv[1] == '--use-default-stations':
        use_default = True
    seed_initial_data(use_default)
