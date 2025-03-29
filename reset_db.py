#!/usr/bin/env python3
"""
Database reset script om de database volledig te resetten en opnieuw te initialiseren.
Gebruik dit script alleen in een ontwikkel- of testomgeving of als je zeker weet dat 
je de productiedatabase wilt resetten!
"""

import os
import sys
from dotenv import load_dotenv

load_dotenv()

from app import app, db
from models import User, Station, DennisStation, Recording, ScheduledJob
from setup_db import setup_database, add_default_dennis_stations

# Veiligheidsmaatregel om te voorkomen dat dit per ongeluk in productie wordt uitgevoerd
CONFIRM_TEXT = "JA_IK_WIL_ALLES_RESETTEN"

def reset_database():
    """Reset de database en initialiseer opnieuw"""
    print("WAARSCHUWING: Dit zal alle gegevens in de database verwijderen!")
    print(f"Typ '{CONFIRM_TEXT}' om te bevestigen:")
    confirmation = input()
    
    if confirmation != CONFIRM_TEXT:
        print("Reset geannuleerd.")
        return
    
    print("Database wordt gereset...")
    with app.app_context():
        # Alles verwijderen
        db.drop_all()
        print("Database schema verwijderd.")
        
        # Schema opnieuw aanmaken
        db.create_all()
        print("Nieuw schema aangemaakt.")
        
        # Basisgegevens toevoegen
        setup_database()
        add_default_dennis_stations()
        print("Standaardgegevens toegevoegd.")
        
        # Check of basisdata is aangemaakt
        user_count = User.query.count()
        station_count = Station.query.count()
        dennis_count = DennisStation.query.count()
        
        print(f"Reset succesvol voltooid. Gemaakt: {user_count} gebruikers, "
              f"{station_count} stations, {dennis_count} Dennis stations.")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--force":
        # Als --force wordt gespecificeerd, sla de bevestiging over
        with app.app_context():
            db.drop_all()
            db.create_all()
            setup_database()
            add_default_dennis_stations()
            print("Database is gereset met --force parameter.")
    else:
        reset_database()