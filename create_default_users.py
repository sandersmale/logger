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
    from werkzeug.security import generate_password_hash
    
    with app.app_context():
        if User.query.count() == 0:
            admin = User(username='admin', role='admin', password_hash=generate_password_hash('radioadmin'))
            editor = User(username='editor', role='editor', password_hash=generate_password_hash('radioeditor'))
            listener = User(username='luisteraar', role='listener', password_hash=generate_password_hash('radioluisteraar'))
            db.session.add(admin)
            db.session.add(editor)
            db.session.add(listener)
            db.session.commit()
            print('✅ Standaard gebruikers aangemaakt')
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken gebruikers: {e}')
    sys.exit(1)