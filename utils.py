import os
import re
import logging
import subprocess
from datetime import datetime, date, timedelta
from app import app

logger = logging.getLogger(__name__)

def check_disk_space():
    """Check available disk space"""
    try:
        disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
        disk_total = os.statvfs(app.config['RECORDINGS_DIR']).f_blocks * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
        
        disk_free_gb = disk_free / (1024**3)
        disk_total_gb = disk_total / (1024**3)
        disk_used_percent = 100 - (disk_free / disk_total * 100)
        
        return {
            'free_gb': round(disk_free_gb, 2),
            'total_gb': round(disk_total_gb, 2),
            'used_percent': round(disk_used_percent, 2),
            'is_low': disk_free_gb < 2
        }
    except Exception as e:
        logger.error(f"Error checking disk space: {e}")
        return None

def format_filesize(size_bytes):
    """Format file size in human-readable format"""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024**2:
        return f"{size_bytes/1024:.1f} KB"
    elif size_bytes < 1024**3:
        return f"{size_bytes/1024**2:.1f} MB"
    else:
        return f"{size_bytes/1024**3:.2f} GB"

def get_running_recordings():
    """Get list of currently running recordings"""
    try:
        output = subprocess.check_output(["pgrep", "-af", "ffmpeg"]).decode('utf-8')
        processes = []
        
        for line in output.splitlines():
            if not line.strip():
                continue
                
            parts = line.split(" ", 1)
            if len(parts) < 2:
                continue
                
            pid = parts[0]
            command = parts[1]
            
            # Extract stream URL
            url_match = re.search(r'-i\s+([^\s]+)', command)
            url = url_match.group(1) if url_match else "Unknown"
            
            # Extract output path
            # Zoek naar het outputpad in het ffmpeg commando
            recordings_dir = app.config.get('RECORDINGS_DIR', 'recordings')
            output_match = re.search(fr'({re.escape(recordings_dir)}/[^\s]+)', command)
            output = output_match.group(1) if output_match else "Unknown"
            
            # Extract station name from output path
            # Het outputpad zou er ongeveer zo uit moeten zien: recordings/stationname/date/hour.mp3
            parts = output.split('/')
            station = parts[1] if len(parts) > 2 else "Unknown"
            
            processes.append({
                'pid': pid,
                'station': station,
                'url': url,
                'output': output
            })
        
        return processes
    
    except subprocess.CalledProcessError:
        # No ffmpeg processes running
        return []
    except Exception as e:
        logger.error(f"Error getting running recordings: {e}")
        return []

def get_ffmpeg_version():
    """Get ffmpeg version information"""
    try:
        output = subprocess.check_output(['ffmpeg', '-version']).decode('utf-8')
        version_match = re.search(r'ffmpeg version\s+([^\s]+)', output)
        return version_match.group(1) if version_match else "Unknown"
    except Exception as e:
        logger.error(f"Error getting ffmpeg version: {e}")
        return "Error"

def clean_folder_name(name):
    """Clean a folder name for filesystem use"""
    # Replace special characters with underscores, EXCEPT spaces
    cleaned = re.sub(r'[^a-zA-Z0-9_\-. ]', '_', name)
    # Remove multiple consecutive underscores
    cleaned = re.sub(r'_{2,}', '_', cleaned)
    # Remove leading and trailing underscores and spaces
    cleaned = cleaned.strip('_ ')
    return cleaned.lower()

def is_valid_stream_url(url):
    """Validate a stream URL format"""
    # Basic URL validation
    if not url:
        return False
    
    try:
        from urllib.parse import urlparse
        parsed = urlparse(url)
        return bool(parsed.scheme and parsed.netloc)
    except Exception:
        return False

def get_date_navigation(selected_date=None, days=7):
    """Generate date navigation for the UI"""
    if selected_date is None:
        selected_date = date.today()
    elif isinstance(selected_date, str):
        try:
            selected_date = datetime.strptime(selected_date, '%Y-%m-%d').date()
        except ValueError:
            selected_date = date.today()
    
    date_nav = []
    today = date.today()
    
    for i in range(days):
        nav_date = today - timedelta(days=i)
        date_nav.append({
            'date': nav_date,
            'formatted': nav_date.strftime('%Y-%m-%d'),
            'display': nav_date.strftime('%d-%m-%Y') + (' (vandaag)' if nav_date == today else ''),
            'active': nav_date == selected_date
        })
    
    return date_nav
