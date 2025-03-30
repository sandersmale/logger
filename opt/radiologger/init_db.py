
#!/usr/bin/env python3
import os
import sys
from pathlib import Path

# Zorg ervoor dat we in de juiste directory zijn
os.chdir('/opt/radiologger')

# Voeg de applicatie directory toe aan Python path
app_dir = Path('/opt/radiologger')
sys.path.insert(0, str(app_dir))

try:
    from app import create_app, db
    
    app = create_app()
    with app.app_context():
        db.create_all()
        print('✅ Database tabellen succesvol aangemaakt')
        
    # Controleer of de tabellen zijn aangemaakt
    with app.app_context():
        tables = db.engine.table_names()
        print(f'Aangemaakte tabellen: {", ".join(tables)}')
    
    sys.exit(0)
except Exception as e:
    print(f'❌ Fout bij aanmaken tabellen: {e}')
    import traceback
    print(traceback.format_exc())
    sys.exit(1)
