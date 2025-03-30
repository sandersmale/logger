
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Voeg de applicatie directory toe aan Python path
app_dir = Path('/opt/radiologger')
sys.path.insert(0, str(app_dir))
os.chdir(str(app_dir))

# Importeer de benodigde modules
try:
    from app import create_app, db
    
    app = create_app()
    with app.app_context():
        db.create_all()
        print('✅ Database tabellen succesvol aangemaakt')
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    sys.exit(1)
