#!/usr/bin/env python3
"""
Reset gebruikers script
Dit script verwijdert alle gebruikers uit de database zodat de setup pagina weer verschijnt.
"""
import os
import sys
from pathlib import Path

# Zorg ervoor dat we in de juiste directory zijn
script_dir = os.path.dirname(os.path.realpath(__file__))
os.chdir(script_dir)
sys.path.insert(0, script_dir)

# Importeer app en database
try:
    from app import db, app
    from models import User
    
    print("Gebruikers resetten...")
    
    with app.app_context():
        user_count = User.query.count()
        if user_count > 0:
            # Verwijder alle gebruikers
            users = User.query.all()
            for user in users:
                db.session.delete(user)
            
            # Commit de wijzigingen
            db.session.commit()
            print(f"✅ {user_count} gebruikers verwijderd. De setup pagina zal nu verschijnen bij het eerste bezoek.")
        else:
            print("Er zijn geen gebruikers om te verwijderen.")
        
    sys.exit(0)
except Exception as e:
    print(f"❌ Fout bij resetten gebruikers: {e}")
    import traceback
    print(traceback.format_exc())
    sys.exit(1)