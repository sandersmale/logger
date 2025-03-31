#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Zorg ervoor dat we in de juiste directory zijn
os.chdir('/opt/radiologger')
base_path = Path('/opt/radiologger')
sys.path.insert(0, str(base_path))

# Voeg de directory toe aan PYTHONPATH
os.environ['PYTHONPATH'] = str(base_path)

try:
    from app import db, app
    from models import User
    
    with app.app_context():
        if User.query.count() == 0:
            print('Geen gebruikers gevonden. Gebruikers worden aangemaakt via de setup pagina bij eerste bezoek.')
        else:
            print(f'Er zijn al {User.query.count()} gebruikers in de database.')
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken gebruikers: {e}')
    sys.exit(1)