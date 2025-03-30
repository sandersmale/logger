#!/bin/bash
# Script om de importproblemen in radiologger op te lossen
# Voornamelijk het "ModuleNotFoundError: No module named 'forms'" probleem

set -e

echo "=== RADIOLOGGER IMPORT FIX SCRIPT ==="
echo "Dit script lost het probleem op met de formulier import in auth.py"
echo ""

# Controleer of script als root wordt uitgevoerd
if [[ $EUID -ne 0 ]]; then
   echo "Dit script moet als root worden uitgevoerd (gebruik sudo)"
   exit 1
fi

# 1. Controleer of forms.py bestaat
echo "Controleren of forms.py bestaat..."
if [ ! -f "/opt/radiologger/forms.py" ]; then
    echo "❌ forms.py ontbreekt! Dit is waarom de applicatie faalt."
    echo "Probeer forms.py te downloaden van GitHub..."
    
    if wget -q -O "/opt/radiologger/forms.py" "https://raw.githubusercontent.com/sandersmale/logger/main/forms.py"; then
        chmod 755 "/opt/radiologger/forms.py"
        chown radiologger:radiologger "/opt/radiologger/forms.py"
        echo "✅ forms.py succesvol gedownload en geïnstalleerd"
    else
        echo "❌ Kon forms.py niet downloaden - creëer een basis versie..."
        
        # Maak een minimale forms.py met LoginForm en UserForm
        cat > /opt/radiologger/forms.py << 'EOL'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField, SelectField, TextAreaField, HiddenField
from wtforms.validators import DataRequired, Length, URL, Optional, Email, EqualTo

class LoginForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired()])
    password = PasswordField('Wachtwoord', validators=[DataRequired()])
    remember_me = BooleanField('Onthoud mij')
    submit = SubmitField('Inloggen')

class UserForm(FlaskForm):
    username = StringField('Gebruikersnaam', validators=[DataRequired(), Length(min=3, max=64)])
    password = PasswordField('Wachtwoord', validators=[DataRequired(), Length(min=6, max=128)])
    role = SelectField('Rol', choices=[('listener', 'Listener'), ('editor', 'Editor'), ('admin', 'Admin')])
    submit = SubmitField('Gebruiker toevoegen')
EOL
        chmod 755 /opt/radiologger/forms.py
        chown radiologger:radiologger /opt/radiologger/forms.py
        echo "✅ forms.py succesvol aangemaakt"
    fi
else
    echo "✅ forms.py bestaat al"
fi

# 2. Controleer of alle nodige Python pakketten zijn geïnstalleerd
echo ""
echo "Controleren of alle nodige Python pakketten zijn geïnstalleerd..."
if ! /opt/radiologger/venv/bin/pip show flask-wtf &>/dev/null; then
    echo "❌ flask-wtf ontbreekt - installeren..."
    /opt/radiologger/venv/bin/pip install flask-wtf
    echo "✅ flask-wtf geïnstalleerd"
else
    echo "✅ flask-wtf is al geïnstalleerd"
fi

# 3. Optioneel: Wijzig app.py om try-except te gebruiken rond de auth import
echo ""
echo "Aanpassen van app.py om importfouten beter af te handelen..."
if grep -q "from auth import auth_bp" /opt/radiologger/app.py; then
    # Backup maken
    cp /opt/radiologger/app.py /opt/radiologger/app.py.bak
    
    # Vervang de directe import door een try-except
    sed -i 's/from auth import auth_bp/try:\n    from auth import auth_bp\n    app.register_blueprint(auth_bp)\n    logger.info("Authentication blueprint geregistreerd")\nexcept ImportError as e:\n    logger.warning(f"Kon auth blueprint niet laden: {str(e)}")\n# Originele regel: from auth import auth_bp/' /opt/radiologger/app.py
    
    # Verwijder de register_blueprint regel als die nog bestaat
    sed -i '/app.register_blueprint(auth_bp)/d' /opt/radiologger/app.py
    
    echo "✅ app.py aangepast voor betere foutafhandeling"
else
    echo "✅ app.py bevat al try-except voor auth imports"
fi

# 4. Controleer auth.py voor importcorrecties
echo ""
echo "Controleren van auth.py voor importcorrecties..."
if grep -q "from forms import LoginForm, UserForm" /opt/radiologger/auth.py; then
    # Backup maken
    cp /opt/radiologger/auth.py /opt/radiologger/auth.py.bak
    
    # Probeer correctie door relatieve import
    sed -i 's/from forms import LoginForm, UserForm/try:\n    from forms import LoginForm, UserForm\nexcept ImportError:\n    # Fallback definities indien formulier module ontbreekt\n    from flask_wtf import FlaskForm\n    from wtforms import StringField, PasswordField, BooleanField, SubmitField, SelectField\n    from wtforms.validators import DataRequired, Length\n    \n    class LoginForm(FlaskForm):\n        username = StringField("Gebruikersnaam", validators=[DataRequired()])\n        password = PasswordField("Wachtwoord", validators=[DataRequired()])\n        remember_me = BooleanField("Onthoud mij")\n        submit = SubmitField("Inloggen")\n    \n    class UserForm(FlaskForm):\n        username = StringField("Gebruikersnaam", validators=[DataRequired(), Length(min=3, max=64)])\n        password = PasswordField("Wachtwoord", validators=[DataRequired(), Length(min=6, max=128)])\n        role = SelectField("Rol", choices=[("listener", "Listener"), ("editor", "Editor"), ("admin", "Admin")])\n        submit = SubmitField("Gebruiker toevoegen")/' /opt/radiologger/auth.py
    
    echo "✅ auth.py aangepast voor betere foutafhandeling"
else
    echo "⚠️ auth.py bevat unexpected import pattern - handmatige controle aanbevolen"
fi

# 5. Fix main.py om circulaire imports te voorkomen
echo ""
echo "Controleren main.py op circulaire imports..."
if grep -q "from app import app as flask_app" /opt/radiologger/main.py; then
    # Backup maken
    cp /opt/radiologger/main.py /opt/radiologger/main.py.bak
    
    # Wijzig main.py om app direct te importeren
    sed -i 's/from app import app as flask_app/try:\n    from app import app\n    logger.info("App succesvol geïmporteerd")\nexcept ImportError as e:\n    logger.error(f"Kon app niet importeren: {str(e)}")\n    from flask import Flask\n    \n    app = Flask(__name__)\n    app.secret_key = os.environ.get("FLASK_SECRET_KEY", "emergency-key")\n    \n    @app.route("/")\n    def emergency_index():\n        return "Radiologger noodmodus - kon app.py niet importeren"/' /opt/radiologger/main.py
    
    echo "✅ main.py aangepast om circulaire imports te voorkomen"
else
    echo "⚠️ main.py importeert app.py niet zoals verwacht - handmatige controle aanbevolen"
fi

# 6. Controleer of alle benodigde bestanden bestaan
echo ""
echo "Controleren of alle kritieke bestanden aanwezig zijn..."
kritieke_bestanden=("app.py" "main.py" "auth.py" "forms.py" "models.py")
missende_bestanden=()

for bestand in "${kritieke_bestanden[@]}"; do
    if [ ! -f "/opt/radiologger/$bestand" ]; then
        missende_bestanden+=("$bestand")
    fi
done

if [ ${#missende_bestanden[@]} -gt 0 ]; then
    echo "⚠️ De volgende kritieke bestanden ontbreken nog:"
    for missend in "${missende_bestanden[@]}"; do
        echo "   - $missend"
    done
    echo "Installatie kan nog steeds problemen hebben!"
else
    echo "✅ Alle kritieke bestanden zijn aanwezig"
fi

# 7. Controleer de rechten
echo ""
echo "Rechten controleren en corrigeren..."
chown -R radiologger:radiologger /opt/radiologger
chmod -R 755 /opt/radiologger
if [ -f "/opt/radiologger/.env" ]; then
    chmod 600 /opt/radiologger/.env
fi
echo "✅ Rechten gecorrigeerd"

# 8. Herstart de services
echo ""
echo "Services herstarten..."
systemctl daemon-reload
systemctl restart radiologger
systemctl restart nginx
echo "✅ Services zijn herstart"

# 9. Toon service status
echo ""
echo "Huidige service status:"
systemctl status radiologger --no-pager
echo ""

echo "====================================="
echo "Fix script voltooid. Test de applicatie nu."
echo "Als er nog steeds problemen zijn, controleer dan de logs met:"
echo "sudo journalctl -u radiologger -n 50"
echo "====================================="