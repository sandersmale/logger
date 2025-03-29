from flask import Blueprint, render_template, request, flash, redirect, url_for, jsonify, send_file, Response, stream_with_context
from flask_login import login_required, current_user
from app import db, app
from models import Recording, Station, DennisStation
from datetime import datetime, date, timedelta
from urllib.parse import quote as url_quote
import os
import subprocess
import boto3
import tempfile
import logging
import requests
from io import BytesIO
from botocore.exceptions import ClientError

player_bp = Blueprint('player', __name__)
logger = logging.getLogger(__name__)

@player_bp.route('/list_recordings')
@login_required
def list_recordings():
    """Hoofdpagina - toont lijst met opnames met uitklapbaar menu"""
    # Get filter parameters
    selected_date = request.args.get('date', date.today().strftime('%Y-%m-%d'))
    selected_station = request.args.get('station', 'all')
    
    try:
        filter_date = datetime.strptime(selected_date, '%Y-%m-%d').date()
    except ValueError:
        filter_date = date.today()
        flash('Ongeldige datum, standaard datum wordt gebruikt', 'warning')
    
    # Create date navigation
    today = date.today()
    date_nav = []
    for i in range(7):
        nav_date = today - timedelta(days=i)
        date_nav.append({
            'date': nav_date,
            'formatted': nav_date.strftime('%Y-%m-%d'),
            'display': nav_date.strftime('%d-%m-%Y') + (' (vandaag)' if nav_date == today else '')
        })
    
    # Get stations for dropdown, geordend op display_order en naam
    stations = Station.query.order_by(Station.display_order, Station.name).all()
    dennis_stations = DennisStation.query.filter_by(visible_in_logger=True).order_by(DennisStation.name).all()
    
    # Query recordings based on filters
    query = Recording.query.filter_by(date=filter_date)
    if selected_station != 'all' and not selected_station.startswith('dennis_'):
        try:
            station_id = int(selected_station)
            query = query.filter_by(station_id=station_id)
        except ValueError:
            pass
    
    recordings = query.join(Station).order_by(Station.name, Recording.hour).all()
    
    # Add Dennis recordings if selected or if showing all
    dennis_recordings = []
    if selected_station.startswith('dennis_') or selected_station == 'all':
        # Als er een specifiek Dennis station is geselecteerd
        selected_dennis_id = None
        if selected_station.startswith('dennis_'):
            try:
                selected_dennis_id = int(selected_station.replace('dennis_', ''))
            except ValueError:
                pass
                
        # Filter Dennis stations indien nodig
        filtered_dennis_stations = dennis_stations
        if selected_dennis_id is not None:
            filtered_dennis_stations = [s for s in dennis_stations if s.id == selected_dennis_id]
            
        for station in filtered_dennis_stations:
            for hour in range(24):
                dennis_recordings.append({
                    'station': station,
                    'date': filter_date,
                    'hour': f"{hour:02d}",
                    'type': 'dennis'
                })
    
    return render_template('list_recordings.html', 
                          title='Opnames',
                          recordings=recordings,
                          dennis_recordings=dennis_recordings,
                          stations=stations,
                          dennis_stations=dennis_stations,
                          selected_date=filter_date,
                          selected_station=selected_station,
                          date_nav=date_nav)

@player_bp.route('/player')
@login_required
def player():
    """Audio player for recordings"""
    # Get parameters
    cloudpath = request.args.get('cloudpath', '')
    if not cloudpath:
        flash('Geen cloudpath opgegeven', 'danger')
        return redirect(url_for('player.list_recordings'))
    
    action = request.args.get('action', '')
    start = request.args.get('start', '')
    end = request.args.get('end', '')
    debug = request.args.get('debug', '0') == '1'
    
    # Determine if it's a Dennis or local recording
    is_dennis = False
    if cloudpath.startswith('dennis/'):
        is_dennis = True
    elif cloudpath.startswith('opnames/'):
        is_dennis = False
    else:
        flash('Ongeldige cloudpath-prefix', 'danger')
        return redirect(url_for('player.list_recordings'))
    
    # Build the URL for streaming
    try:
        if is_dennis:
            # Extract folder, date, hour from dennis/folder/date/hour.mp3
            parts = cloudpath.split('/')
            if len(parts) < 4:
                raise ValueError("Ongeldig Dennis cloudpath formaat")
                
            folder = parts[1]
            date_str = parts[2]
            hour = parts[3].replace('.mp3', '')
            
            final_url = f"{app.config['DENNIS_API_URL']}{folder}/{folder}-{date_str}-{hour}.mp3"
            custom_filename = f"{folder}-{date_str}-{hour}.mp3"
        else:
            # Local recordings: use S3 presigned URL
            s3_path = cloudpath
            if not s3_path.endswith('.mp3'):
                s3_path += '.mp3'
                
            # Generate S3 presigned URL
            s3_client = boto3.client(
                's3',
                endpoint_url=app.config['S3_ENDPOINT'],
                region_name=app.config['S3_REGION']
            )
            
            try:
                final_url = s3_client.generate_presigned_url(
                    'get_object',
                    Params={'Bucket': app.config['S3_BUCKET'], 'Key': s3_path},
                    ExpiresIn=3600
                )
                
                # Extract filename parts
                parts = s3_path.split('/')
                if len(parts) >= 4:
                    station = parts[1]
                    date_part = parts[2]
                    file_part = parts[3]
                    custom_filename = f"{station}-{date_part}-{file_part}"
                else:
                    custom_filename = os.path.basename(s3_path)
            except ClientError as e:
                logger.error(f"Error generating presigned URL: {e}")
                flash('Kon geen presigned URL genereren voor streaming', 'danger')
                return redirect(url_for('player.list_recordings'))
        
        # Handle download action
        if action == 'download':
            if start and end:
                # Fragment download
                try:
                    start_float = float(start)
                    end_float = float(end)
                    if end_float <= start_float:
                        flash('Eindtijd moet na begintijd liggen', 'danger')
                        return redirect(url_for('player.player', cloudpath=cloudpath))
                        
                    duration = end_float - start_float
                    filename_base = custom_filename.replace('.mp3', '')
                    download_filename = f"{filename_base}_fragment_{start}_{end}.mp3"
                    
                    return stream_audio_fragment(final_url, start_float, duration, download_filename)
                except ValueError:
                    flash('Ongeldige start- of eindtijd', 'danger')
                    return redirect(url_for('player.player', cloudpath=cloudpath))
            else:
                # Full download
                return stream_full_audio(final_url, custom_filename)
        
        # Streaming mode (default)
        return render_template('player.html', 
                              title='Opname Player',
                              final_url=final_url,
                              cloudpath=cloudpath,
                              custom_filename=custom_filename,
                              debug=debug)
    
    except Exception as e:
        logger.error(f"Error in player: {e}")
        flash(f'Fout bij het laden van de opname: {str(e)}', 'danger')
        return redirect(url_for('player.list_recordings'))

def stream_audio_fragment(url, start_time, duration, filename):
    """Stream a fragment of audio using ffmpeg"""
    try:
        ffmpeg_cmd = [
            app.config['FFMPEG_PATH'],
            '-ss', str(start_time),
            '-i', url,
            '-t', str(duration),
            '-c', 'copy',
            '-f', 'mp3',
            'pipe:1'
        ]
        
        process = subprocess.Popen(ffmpeg_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        def generate():
            try:
                while True:
                    data = process.stdout.read(4096)
                    if not data:
                        break
                    yield data
            finally:
                process.kill()
                
        return Response(
            stream_with_context(generate()),
            mimetype='audio/mpeg',
            headers={
                'Content-Disposition': f'attachment; filename="{url_quote(filename)}"'
            }
        )
    except Exception as e:
        logger.error(f"Error streaming audio fragment: {e}")
        flash(f'Fout bij het downloaden van het fragment: {str(e)}', 'danger')
        return redirect(url_for('player.player', cloudpath=request.args.get('cloudpath', '')))

def stream_full_audio(url, filename):
    """Stream the full audio file for download"""
    try:
        # Stream the file via requests to avoid loading it entirely in memory
        response = requests.get(url, stream=True)
        if response.status_code != 200:
            flash(f'Fout bij het downloaden: HTTP {response.status_code}', 'danger')
            return redirect(url_for('player.player', cloudpath=request.args.get('cloudpath', '')))
            
        def generate():
            for chunk in response.iter_content(chunk_size=4096):
                yield chunk
                
        return Response(
            stream_with_context(generate()),
            mimetype='audio/mpeg',
            headers={
                'Content-Disposition': f'attachment; filename="{url_quote(filename)}"',
                'Content-Length': response.headers.get('Content-Length')
            }
        )
    except Exception as e:
        logger.error(f"Error streaming full audio: {e}")
        flash(f'Fout bij het downloaden: {str(e)}', 'danger')
        return redirect(url_for('player.player', cloudpath=request.args.get('cloudpath', '')))
