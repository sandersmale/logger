from flask import render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from app import app, db
from models import Station, Recording, DennisStation, User
from auth import admin_required, editor_required
from forms import StationForm, SetupForm
from werkzeug.security import generate_password_hash
import os
from dotenv import load_dotenv
import sys
import subprocess
import psutil
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

# Register global template functions and variables
@app.context_processor
def inject_now():
    return {'now': datetime.now()}

@app.route('/')
def index():
    """Homepage - controleert setup en stuurt door naar de juiste pagina"""
    # Controleer of er gebruikers zijn (setup is voltooid)
    user_count = User.query.count()
    if user_count == 0:
        # Eerste keer setup nodig - alleen voor admin account aanmaken
        # Wasabi-configuratie zou al moeten gebeurd zijn tijdens installatie
        return redirect(url_for('setup'))
    
    # Normale flow als setup voltooid is
    if not current_user.is_authenticated:
        return redirect(url_for('auth.login'))
    
    # Direct doorsturen naar lijst met opnames (hoofdpagina)
    return redirect(url_for('player.list_recordings'))

@app.route('/admin')
@login_required
def admin():
    """Statuspagina - toont informatie over lopende opnames en systeemstatus"""
    from utils import get_running_recordings, check_disk_space, get_ffmpeg_version
    from models import ScheduledJob
    import psutil
    
    # Systeeminformatie
    disk_space = check_disk_space()
    ffmpeg_version = get_ffmpeg_version()
    cpu_percent = psutil.cpu_percent(interval=0.1)
    memory = psutil.virtual_memory()
    
    # Actuele opnames en jobs
    running_recordings = get_running_recordings()
    
    # Scheduled jobs status
    running_jobs = ScheduledJob.query.filter_by(status='running').all()
    scheduled_jobs = ScheduledJob.query.filter_by(status='scheduled').all()
    
    # Station en opname statistieken
    total_recordings = Recording.query.count()
    total_stations = Station.query.count()
    always_on_stations = Station.query.filter_by(always_on=True).count()
    scheduled_stations = Station.query.filter(
        (Station.schedule_start_date != None) & 
        (Station.schedule_end_date != None)
    ).count()
    
    dennis_count = DennisStation.query.count()
    dennis_visible = DennisStation.query.filter_by(visible_in_logger=True).count()
    
    # Vandaag gemaakte opnames
    today = datetime.now().date()
    todays_recordings = Recording.query.filter_by(date=today).count()
    
    stats = {
        'total_recordings': total_recordings,
        'total_stations': total_stations,
        'always_on_stations': always_on_stations,
        'scheduled_stations': scheduled_stations,
        'dennis_count': dennis_count,
        'dennis_visible': dennis_visible,
        'todays_recordings': todays_recordings,
        'system': {
            'disk_space': disk_space,
            'cpu_percent': cpu_percent,
            'memory_percent': memory.percent,
            'memory_used': memory.used // (1024 * 1024),  # MB
            'memory_total': memory.total // (1024 * 1024),  # MB
            'ffmpeg_version': ffmpeg_version
        }
    }
    
    return render_template('admin.html', 
                          title='Radiologger Status', 
                          running_recordings=running_recordings,
                          running_jobs=running_jobs,
                          scheduled_jobs=scheduled_jobs,
                          stats=stats,
                          current_user=current_user)

@app.route('/debug_info')
@admin_required
def debug_info():
    """Show debug information for administrators"""
    info = {
        'recordings_dir': app.config['RECORDINGS_DIR'],
        'logs_dir': app.config['LOGS_DIR'],
        'ffmpeg_path': app.config['FFMPEG_PATH'],
        's3_bucket': app.config['S3_BUCKET'],
        's3_endpoint': app.config['S3_ENDPOINT'],
        'python_version': sys.version,
        'local_time': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'db_uri': app.config['SQLALCHEMY_DATABASE_URI'].split('@')[-1] if '@' in app.config['SQLALCHEMY_DATABASE_URI'] else app.config['SQLALCHEMY_DATABASE_URI']
    }
    
    # Get disk space info
    try:
        disk_total = os.statvfs(app.config['RECORDINGS_DIR']).f_blocks * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
        disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
        info['disk_total_gb'] = round(disk_total / (1024**3), 2)
        info['disk_free_gb'] = round(disk_free / (1024**3), 2)
        info['disk_used_percent'] = round((1 - (disk_free / disk_total)) * 100, 2)
    except Exception as e:
        logger.error(f"Error getting disk space info: {e}")
        info['disk_space_error'] = str(e)
    
    return render_template('debug_info.html', 
                          title='Debug Informatie', 
                          info=info)

@app.route('/health')
def health_check():
    """Simple health check endpoint"""
    status = {
        'database': 'unknown',
        'disk_space': 'unknown',
        'logs_dir': 'unknown',
        'ffmpeg': 'unknown',
        'overall': 'unknown',
        'details': {}
    }
    
    # Check if database is accessible
    try:
        db.session.execute("SELECT 1")
        status['database'] = 'healthy'
        status['details']['database'] = 'Database connection successful'
    except Exception as e:
        status['database'] = 'error'
        status['details']['database'] = str(e)
        logger.error(f"Database health check failed: {e}")
    
    # Check disk space
    try:
        disk_free_gb = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize / (1024**3)
        status['disk_space'] = 'healthy' if disk_free_gb > 2 else 'warning'
        status['details']['disk_space'] = f'{round(disk_free_gb, 2)} GB free'
    except Exception as e:
        status['disk_space'] = 'error'
        status['details']['disk_space'] = str(e)
        logger.error(f"Disk space health check failed: {e}")
    
    # Check logs directory
    try:
        if os.path.isdir(app.config['LOGS_DIR']):
            status['logs_dir'] = 'healthy'
            status['details']['logs_dir'] = f"Directory exists: {app.config['LOGS_DIR']}"
        else:
            status['logs_dir'] = 'error'
            status['details']['logs_dir'] = f"Directory not found: {app.config['LOGS_DIR']}"
    except Exception as e:
        status['logs_dir'] = 'error'
        status['details']['logs_dir'] = str(e)
        logger.error(f"Logs directory health check failed: {e}")
    
    # Check ffmpeg
    try:
        result = subprocess.run(['ffmpeg', '-version'], 
                              stdout=subprocess.PIPE, 
                              stderr=subprocess.PIPE, 
                              text=True,
                              timeout=5)
        if result.returncode == 0:
            ffmpeg_version = result.stdout.splitlines()[0] if result.stdout else "Unknown version"
            status['ffmpeg'] = 'healthy'
            status['details']['ffmpeg'] = ffmpeg_version
        else:
            status['ffmpeg'] = 'error'
            status['details']['ffmpeg'] = f"FFmpeg error: {result.stderr}"
    except Exception as e:
        status['ffmpeg'] = 'error'
        status['details']['ffmpeg'] = str(e)
        logger.error(f"FFmpeg health check failed: {e}")
    
    # Determine overall status
    if 'error' in status.values():
        status['overall'] = 'error'
        http_status = 500
    elif 'warning' in status.values():
        status['overall'] = 'warning'
        http_status = 200
    else:
        status['overall'] = 'healthy'
        http_status = 200
    
    response = {
        'status': status['overall'],
        'timestamp': datetime.now().isoformat(),
        'checks': {k: v for k, v in status.items() if k != 'details' and k != 'overall'},
        'details': status['details']
    }
    
    return jsonify(response), http_status

@app.errorhandler(404)
def not_found_error(error):
    return render_template('error.html', title='Pagina Niet Gevonden', 
                          error_code=404, error_message='De opgevraagde pagina kon niet worden gevonden.'), 404

@app.route('/setup', methods=['GET', 'POST'])
def setup():
    """Eerste keer setup-pagina voor het aanmaken van admin gebruiker (Wasabi-configuratie gebeurt tijdens installatie)"""
    # Controleer of er al gebruikers zijn
    user_count = User.query.count()
    if user_count > 0:
        flash('Setup is al voltooid. Er zijn al gebruikers aangemaakt.', 'info')
        return redirect(url_for('index'))
    
    # Aangepaste versie van het formulier zonder Wasabi velden
    form = SetupForm()
    
    # Controleer of Wasabi-gegevens al ingesteld zijn
    wasabi_configured = bool(app.config.get('WASABI_ACCESS_KEY') and app.config.get('WASABI_SECRET_KEY') and app.config.get('WASABI_BUCKET'))
    
    if form.validate_on_submit():
        try:
            # Maak de admin gebruiker aan
            admin_user = User(
                username=form.admin_username.data,
                role='admin'
            )
            admin_user.set_password(form.admin_password.data)
            db.session.add(admin_user)
            
            # Alleen Wasabi gegevens updaten als ze met het formulier zijn ingediend
            # EN als ze nog niet geconfigureerd waren tijdens installatie
            if not wasabi_configured and hasattr(form, 'wasabi_access_key') and form.wasabi_access_key.data:
                env_path = '.env'
                prod_path = '/opt/radiologger/.env'  # Productie path
                
                # Bepaal welk .env bestand we moeten updaten
                if os.path.exists(prod_path):
                    env_path = prod_path
                    
                if os.path.exists(env_path):
                    try:
                        # Lees het bestand
                        with open(env_path, 'r') as file:
                            env_lines = file.readlines()
                        
                        # Bijwerken van Wasabi configuratie
                        wasabi_lines = {
                            'WASABI_ACCESS_KEY': form.wasabi_access_key.data,
                            'WASABI_SECRET_KEY': form.wasabi_secret_key.data,
                            'WASABI_BUCKET': form.wasabi_bucket.data,
                            'WASABI_REGION': form.wasabi_region.data,
                            'WASABI_ENDPOINT_URL': f'https://s3.{form.wasabi_region.data}.wasabisys.com'
                        }
                        
                        # Update bestaande regels of voeg nieuwe toe
                        updated_lines = []
                        for line in env_lines:
                            key = line.split('=')[0].strip() if '=' in line else None
                            if key in wasabi_lines:
                                updated_lines.append(f"{key}={wasabi_lines[key]}\n")
                                wasabi_lines.pop(key)
                            else:
                                updated_lines.append(line)
                        
                        # Voeg eventuele ontbrekende Wasabi-configuratie toe
                        for key, value in wasabi_lines.items():
                            updated_lines.append(f"{key}={value}\n")
                        
                        # Schrijf terug naar .env bestand
                        with open(env_path, 'w') as file:
                            file.writelines(updated_lines)
                        
                        # Zorg ervoor dat de bestandsrechten correct zijn in productiemodus
                        if env_path == prod_path:
                            os.system(f"chown radiologger:radiologger {env_path}")
                            os.system(f"chmod 640 {env_path}")
                        
                        # Update app config met nieuwe waarden
                        app.config['WASABI_ACCESS_KEY'] = form.wasabi_access_key.data
                        app.config['WASABI_SECRET_KEY'] = form.wasabi_secret_key.data
                        app.config['WASABI_BUCKET'] = form.wasabi_bucket.data
                        app.config['WASABI_REGION'] = form.wasabi_region.data
                        app.config['WASABI_ENDPOINT_URL'] = f'https://s3.{form.wasabi_region.data}.wasabisys.com'
                        
                        # S3 aliassen ook bijwerken
                        app.config['S3_ACCESS_KEY'] = form.wasabi_access_key.data
                        app.config['S3_SECRET_KEY'] = form.wasabi_secret_key.data
                        app.config['S3_BUCKET'] = form.wasabi_bucket.data
                        app.config['S3_REGION'] = form.wasabi_region.data
                        app.config['S3_ENDPOINT'] = f'https://s3.{form.wasabi_region.data}.wasabisys.com'
                    except Exception as e:
                        logger.error(f"Fout bij updaten van .env bestand: {e}")
                        flash(f"Waarschuwing: De Wasabi configuratie kon niet worden opgeslagen in het .env bestand: {e}", "warning")
            
            # Commit wijzigingen naar database
            db.session.commit()
            
            flash('Setup succesvol voltooid! Je kunt nu inloggen met je administrator account.', 'success')
            return render_template('setup.html', title='Radiologger Setup', form=form, success=True, wasabi_configured=wasabi_configured)
        
        except Exception as e:
            db.session.rollback()
            logger.error(f"Setup error: {e}")
            flash(f'Er is een fout opgetreden bij de setup: {str(e)}', 'danger')
    
    return render_template('setup.html', title='Radiologger Setup', form=form, success=False, wasabi_configured=wasabi_configured)

@app.errorhandler(500)
def internal_error(error):
    db.session.rollback()  # Roll back any failed database transactions
    logger.error(f"Internal server error: {error}")
    return render_template('error.html', title='Server Fout', 
                          error_code=500, error_message='Er is een serverfout opgetreden.'), 500
