import os
from app import app, db
from models import User, Station, DennisStation
from werkzeug.security import generate_password_hash
from datetime import datetime, timedelta

def seed_initial_data():
    """
    Seed initial data in the database.
    Only runs when the database is empty.
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
        
        # Create some example stations
        stations = [
            {
                'name': 'NPO Radio 1',
                'recording_url': 'https://icecast.omroep.nl/radio1-bb-mp3',
                'always_on': True
            },
            {
                'name': 'NPO Radio 2',
                'recording_url': 'https://icecast.omroep.nl/radio2-bb-mp3',
                'always_on': False,
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
                'always_on': False
            },
            {
                'name': 'NPO Radio 4',
                'recording_url': 'https://icecast.omroep.nl/radio4-bb-mp3',
                'always_on': False
            },
            {
                'name': 'NPO Radio 5',
                'recording_url': 'https://icecast.omroep.nl/radio5-bb-mp3',
                'always_on': False
            },
            {
                'name': 'NPO Soul & Jazz',
                'recording_url': 'https://icecast.omroep.nl/radio6-bb-mp3',
                'always_on': False
            }
        ]
        
        for station_data in stations:
            station = Station(
                name=station_data['name'],
                recording_url=station_data['recording_url'],
                always_on=station_data['always_on']
            )
            
            if 'schedule' in station_data:
                station.schedule_start_date = station_data['schedule']['start_date']
                station.schedule_start_hour = station_data['schedule']['start_hour']
                station.schedule_end_date = station_data['schedule']['end_date']
                station.schedule_end_hour = station_data['schedule']['end_hour']
                station.record_reason = station_data['schedule']['reason']
            
            db.session.add(station)
        
        # Create some Dennis stations
        dennis_stations = [
            {
                'folder': 'nporadio1',
                'name': 'NPO Radio 1',
                'url': 'https://icecast.omroep.nl/radio1-bb-mp3',
                'visible_in_logger': True
            },
            {
                'folder': 'nporadio2',
                'name': 'NPO Radio 2',
                'url': 'https://icecast.omroep.nl/radio2-bb-mp3',
                'visible_in_logger': True
            },
            {
                'folder': 'npo3fm',
                'name': 'NPO 3FM',
                'url': 'https://icecast.omroep.nl/3fm-bb-mp3',
                'visible_in_logger': False
            },
            {
                'folder': 'nporadio4',
                'name': 'NPO Radio 4',
                'url': 'https://icecast.omroep.nl/radio4-bb-mp3',
                'visible_in_logger': False
            },
            {
                'folder': 'nporadio5',
                'name': 'NPO Radio 5',
                'url': 'https://icecast.omroep.nl/radio5-bb-mp3',
                'visible_in_logger': True
            }
        ]
        
        for station_data in dennis_stations:
            station = DennisStation(
                folder=station_data['folder'],
                name=station_data['name'],
                url=station_data['url'],
                visible_in_logger=station_data['visible_in_logger'],
                last_updated=datetime.now()
            )
            
            db.session.add(station)
        
        db.session.commit()
        print("Initial data seeded successfully!")

if __name__ == '__main__':
    seed_initial_data()
