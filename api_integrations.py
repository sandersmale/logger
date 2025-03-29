from flask import Blueprint, render_template, request, redirect, url_for, flash, jsonify
from flask_login import login_required, current_user
from app import db, app
from models import DennisStation
from forms import DennisStationForm
from auth import editor_required, admin_required
import requests
import json
import os
import subprocess
import logging
from datetime import datetime, date, timedelta
import re

api_bp = Blueprint('api', __name__)
logger = logging.getLogger(__name__)

@api_bp.route('/dennis')
@editor_required
def dennis_stations():
    """Manage Dennis' stations"""
    stations = DennisStation.query.order_by(DennisStation.name).all()
    
    # Separate stations based on visibility
    visible_stations = [s for s in stations if s.visible_in_logger]
    hidden_stations = [s for s in stations if not s.visible_in_logger]
    
    return render_template('dennis.html',
                          title="Dennis' Stations Beheer",
                          visible_stations=visible_stations,
                          hidden_stations=hidden_stations)

@api_bp.route('/update_dennis_api')
@editor_required
def update_dennis_api():
    """Refresh the list of Dennis' stations from the API"""
    try:
        result = refresh_dennis_api()
        if result['success']:
            flash(f"De lijst is succesvol ververst. {result['added']} stations toegevoegd, {result['updated']} bijgewerkt.", 'success')
        else:
            flash(f"Fout bij vernieuwen van de lijst: {result['error']}", 'danger')
    except Exception as e:
        logger.error(f"Error refreshing Dennis API: {e}")
        flash(f"Fout bij vernieuwen van de lijst: {str(e)}", 'danger')
    
    return redirect(url_for('api.dennis_stations'))

@api_bp.route('/update_stations', methods=['POST'])
@editor_required
def update_stations():
    """Update the visibility of Dennis' stations in the logger"""
    form = DennisStationForm()
    
    if form.validate_on_submit():
        selected_ids = []
        if form.stations.data:
            try:
                selected_ids = json.loads(form.stations.data)
            except json.JSONDecodeError:
                selected_ids = []
        
        # Get all station IDs
        all_ids = [s.id for s in DennisStation.query.all()]
        
        # Update visibility
        for station_id in all_ids:
            station = DennisStation.query.get(station_id)
            if station:
                station.visible_in_logger = (station_id in selected_ids)
                station.last_updated = datetime.utcnow()
        
        try:
            db.session.commit()
            flash('Stationslijst succesvol bijgewerkt', 'success')
        except Exception as e:
            db.session.rollback()
            logger.error(f"Error updating Dennis stations: {e}")
            flash(f'Fout bij het bijwerken van de stationslijst: {str(e)}', 'danger')
    
    return redirect(url_for('api.dennis_stations'))

def refresh_dennis_api():
    """Fetch the latest station data from Dennis' API"""
    try:
        # This is a placeholder - in a real implementation, you would call the actual API
        # Since we don't have direct access to the API, we'll simulate it
        
        # In a real implementation, we might do something like:
        # response = requests.get('https://api.dennisserver.nl/stations')
        # dennis_data = response.json()
        
        # For now, we'll do a simplified version based on the PHP implementation
        api_url = "https://logger.dennishoogeveenmedia.nl/api/stations.json"
        
        response = requests.get(api_url, timeout=10)
        if response.status_code != 200:
            return {
                'success': False,
                'error': f"API returned status code {response.status_code}"
            }
        
        try:
            dennis_data = response.json()
        except json.JSONDecodeError:
            return {
                'success': False,
                'error': "Invalid JSON response from API"
            }
        
        # Track changes
        added = 0
        updated = 0
        
        # Process stations
        for station_data in dennis_data:
            folder = station_data.get('folder', '')
            name = station_data.get('name', '')
            url = station_data.get('url', '')
            
            if not folder or not name or not url:
                continue
            
            # Check if station exists
            station = DennisStation.query.filter_by(folder=folder).first()
            
            if station:
                # Update existing station
                station.name = name
                station.url = url
                station.last_updated = datetime.utcnow()
                updated += 1
            else:
                # Add new station
                station = DennisStation(
                    folder=folder,
                    name=name,
                    url=url,
                    visible_in_logger=False,
                    last_updated=datetime.utcnow()
                )
                db.session.add(station)
                added += 1
        
        db.session.commit()
        
        return {
            'success': True,
            'added': added,
            'updated': updated
        }
    
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error refreshing Dennis API: {e}")
        return {
            'success': False,
            'error': str(e)
        }

@api_bp.route('/download_omroeplvc')
@admin_required
def download_omroeplvc():
    """Manually trigger Omroep LvC download"""
    try:
        current_hour = datetime.now().hour
        current_date = date.today()
        
        # Determine day abbreviation (ma, di, wo, do, vr, za, zo)
        day_names = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo']
        day_abbr = day_names[current_date.weekday()]
        
        # Build the URL
        file_name = f"{day_abbr}{current_hour:02d}.mp3"
        remote_url = f"{app.config['OMROEP_LVC_URL']}{file_name}"
        
        # Local path
        local_dir = os.path.join(app.config['RECORDINGS_DIR'], 'omroep land van cuijk', current_date.strftime('%Y-%m-%d'))
        os.makedirs(local_dir, exist_ok=True)
        local_file = os.path.join(local_dir, f"{current_hour:02d}.mp3")
        
        # Download the file
        response = requests.get(remote_url, stream=True)
        if response.status_code != 200:
            return {
                'success': False,
                'error': f"Download failed with status code {response.status_code}"
            }
        
        # Check if response is HTML (error page)
        content_type = response.headers.get('content-type', '')
        if 'text/html' in content_type or response.text.strip().startswith('<!DOCTYPE html>'):
            return {
                'success': False,
                'error': "Received HTML instead of audio file (program might not be available)"
            }
        
        # Save the file
        with open(local_file, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        flash(f"Omroep LvC uitzending voor {current_date.strftime('%Y-%m-%d')} {current_hour:02d}:00 succesvol gedownload", 'success')
        return redirect(url_for('admin'))
    
    except Exception as e:
        logger.error(f"Error downloading Omroep LvC: {e}")
        flash(f"Fout bij het downloaden van Omroep LvC: {str(e)}", 'danger')
        return redirect(url_for('admin'))
