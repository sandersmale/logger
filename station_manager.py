from flask import Blueprint, render_template, request, redirect, url_for, flash, jsonify
from flask_login import login_required, current_user
from app import db, app
from models import Station, Recording
from forms import StationForm, TestStreamForm
from auth import editor_required, admin_required
from datetime import datetime
from stream_utils import test_stream
import logging
import os
from storage import list_s3_files, count_station_recordings
from logger import start_manual_recording, stop_recording

station_bp = Blueprint('station', __name__)
logger = logging.getLogger(__name__)

@station_bp.route('/manage_stations')
@editor_required
def manage_stations():
    """List all stations with management options"""
    # Sorteer stations op display_order en dan op naam
    stations = Station.query.order_by(Station.display_order, Station.name).all()
    
    # Get recording counts for each station
    station_counts = {}
    for station in stations:
        station_counts[station.id] = count_station_recordings(station.id)
    
    return render_template('manage_stations.html',
                          title='Stations Beheer',
                          stations=stations,
                          station_counts=station_counts)

@station_bp.route('/add_station', methods=['GET', 'POST'])
@editor_required
def add_station():
    """Add a new station"""
    form = StationForm()
    
    if form.validate_on_submit():
        # Test stream before adding
        try:
            test_result = test_stream(form.recording_url.data)
            if not test_result.get('status') == 'OK':
                flash('Stream test mislukt: ' + test_result.get('error', 'Onbekende fout'), 'danger')
                return redirect(url_for('station.add_station'))
        except Exception as e:
            flash('Stream test mislukt: ' + str(e), 'danger')
            return redirect(url_for('station.add_station'))
            
        # Check if station already exists
        if Station.query.filter_by(name=form.name.data).first():
            flash('Station met deze naam bestaat al', 'danger')
            return redirect(url_for('station.add_station'))
        
        # Create new station
        station = Station(
            name=form.name.data,
            recording_url=form.recording_url.data,
            always_on=not form.has_schedule.data
        )
        
        # Add schedule if specified
        if form.has_schedule.data:
            try:
                station.schedule_start_date = datetime.strptime(request.form['schedule_start_date'], '%Y-%m-%d').date()
                station.schedule_start_hour = int(request.form['schedule_start_hour'])
                station.schedule_end_date = datetime.strptime(request.form['schedule_end_date'], '%Y-%m-%d').date()
                station.schedule_end_hour = int(request.form['schedule_end_hour'])
                station.record_reason = form.record_reason.data
            except (ValueError, KeyError) as e:
                flash('Ongeldige datum/tijd waarden', 'danger')
                return redirect(url_for('station.add_station'))
        
        try:
            db.session.add(station)
            db.session.commit()
            flash(f'Station "{form.name.data}" succesvol toegevoegd', 'success')
            return redirect(url_for('station.manage_stations'))
        except Exception as e:
            db.session.rollback()
            logger.error(f"Error adding station: {e}")
            flash(f'Fout bij het toevoegen van het station: {str(e)}', 'danger')
    
    return render_template('add_station.html', 
                          title='Station Toevoegen',
                          form=form,
                          test_form=test_form)

@station_bp.route('/edit_station/<int:station_id>', methods=['GET', 'POST'])
@editor_required
def edit_station(station_id):
    """Edit an existing station"""
    station = Station.query.get_or_404(station_id)
    form = StationForm(obj=station)
    test_form = TestStreamForm()
    
    if request.method == 'GET':
        form.has_schedule.data = (station.schedule_start_date is not None)
    
    if form.validate_on_submit():
        # Check if new name already exists (if name changed)
        if form.name.data != station.name and Station.query.filter_by(name=form.name.data).first():
            flash('Station met deze naam bestaat al', 'danger')
            return redirect(url_for('station.edit_station', station_id=station_id))
        
        # Update station
        station.name = form.name.data
        station.recording_url = form.recording_url.data
        station.always_on = form.always_on.data
        
        # Update schedule
        if form.has_schedule.data:
            station.schedule_start_date = form.schedule_start_date.data
            station.schedule_start_hour = int(form.schedule_start_hour.data)
            station.schedule_end_date = form.schedule_end_date.data
            station.schedule_end_hour = int(form.schedule_end_hour.data)
            station.record_reason = form.record_reason.data
        else:
            station.schedule_start_date = None
            station.schedule_start_hour = None
            station.schedule_end_date = None
            station.schedule_end_hour = None
            station.record_reason = None
        
        try:
            db.session.commit()
            flash(f'Station "{form.name.data}" succesvol bijgewerkt', 'success')
            return redirect(url_for('station.manage_stations'))
        except Exception as e:
            db.session.rollback()
            logger.error(f"Error updating station: {e}")
            flash(f'Fout bij het bijwerken van het station: {str(e)}', 'danger')
    
    return render_template('edit_station.html',
                          title=f'Station Bewerken: {station.name}',
                          form=form,
                          test_form=test_form,
                          station=station)

@station_bp.route('/delete_station/<int:station_id>')
@admin_required
def delete_station(station_id):
    """Delete a station"""
    station = Station.query.get_or_404(station_id)
    station_name = station.name
    
    # Check for recordings
    recordings_count = Recording.query.filter_by(station_id=station_id).count()
    if recordings_count > 0 and not request.args.get('confirm'):
        flash(f'Station "{station_name}" heeft {recordings_count} opnames. Bevestig verwijdering.', 'warning')
        return redirect(url_for('station.manage_stations', delete_station=station_id, recording_count=recordings_count))
    
    try:
        # Start transaction
        db.session.begin_nested()
        
        # Stop any active recordings
        stop_recording(station_id)
        
        # Delete all scheduled jobs for this station
        ScheduledJob.query.filter_by(station_id=station_id).delete()
        
        # Delete all recordings for this station
        Recording.query.filter_by(station_id=station_id).delete()
        
        # Delete the station
        db.session.delete(station)
        
        # Commit the transaction
        db.session.commit()
        flash(f'Station "{station_name}" succesvol verwijderd', 'success')
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error deleting station: {e}")
        flash(f'Fout bij het verwijderen van het station: {str(e)}', 'danger')
    
    return redirect(url_for('station.manage_stations'))

@station_bp.route('/start_manual/<int:station_id>')
@editor_required
def start_manual(station_id):
    """Start a manual recording"""
    station = Station.query.get_or_404(station_id)
    
    try:
        # Check disk space
        disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
        disk_free_gb = disk_free / (1024**3)
        
        if disk_free_gb < 2:
            flash(f'Onvoldoende schijfruimte: {disk_free_gb:.2f} GB beschikbaar', 'danger')
            return redirect(url_for('station.manage_stations'))
        
        result = start_manual_recording(station_id)
        if result['success']:
            flash(f'Handmatige opname voor "{station.name}" gestart', 'success')
        else:
            flash(f'Fout bij het starten van de opname: {result["error"]}', 'danger')
    except Exception as e:
        logger.error(f"Error starting manual recording: {e}")
        flash(f'Fout bij het starten van de opname: {str(e)}', 'danger')
    
    return redirect(url_for('station.manage_stations'))

@station_bp.route('/stop_recording/<int:station_id>')
@editor_required
def stop_station_recording(station_id):
    """Stop recording for a station"""
    station = Station.query.get_or_404(station_id)
    
    try:
        result = stop_recording(station_id)
        if result['success']:
            flash(f'Opname voor "{station.name}" gestopt', 'success')
        else:
            flash(f'Fout bij het stoppen van de opname: {result["error"]}', 'danger')
    except Exception as e:
        logger.error(f"Error stopping recording: {e}")
        flash(f'Fout bij het stoppen van de opname: {str(e)}', 'danger')
    
    return redirect(url_for('station.manage_stations'))

@station_bp.route('/test_stream', methods=['POST'])
@editor_required
def test_stream_endpoint():
    """Test a stream URL"""
    form = TestStreamForm()
    
    if form.validate_on_submit():
        try:
            result = test_stream(form.url.data)
            if result['success']:
                return jsonify({
                    'status': 'OK',
                    'stream_url': result['stream_url'],
                    'message': 'Stream test succesvol'
                })
            else:
                return jsonify({
                    'status': 'error',
                    'message': result['error']
                }), 400
        except Exception as e:
            logger.error(f"Error testing stream: {e}")
            return jsonify({
                'status': 'error',
                'message': f'Fout bij het testen van de stream: {str(e)}'
            }), 500
    
    return jsonify({
        'status': 'error',
        'message': 'Ongeldige formuliergegevens'
    }), 400

@station_bp.route('/move_station_up/<int:station_id>')
@editor_required
def move_station_up(station_id):
    """Verplaats een station omhoog in de volgorde"""
    station = Station.query.get_or_404(station_id)
    
    try:
        # Zoek het station met de hoogste display_order die lager is dan deze
        previous_station = Station.query.filter(
            Station.display_order < station.display_order
        ).order_by(Station.display_order.desc()).first()
        
        if previous_station:
            # Verwissel de display_order waarden
            temp_order = previous_station.display_order
            previous_station.display_order = station.display_order
            station.display_order = temp_order
            db.session.commit()
            flash(f'Station "{station.name}" naar boven verplaatst', 'success')
        else:
            flash(f'Station "{station.name}" staat al helemaal bovenaan', 'info')
            
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error moving station up: {e}")
        flash(f'Fout bij het verplaatsen van het station: {str(e)}', 'danger')
    
    return redirect(url_for('station.manage_stations'))

@station_bp.route('/move_station_down/<int:station_id>')
@editor_required
def move_station_down(station_id):
    """Verplaats een station omlaag in de volgorde"""
    station = Station.query.get_or_404(station_id)
    
    try:
        # Zoek het station met de laagste display_order die hoger is dan deze
        next_station = Station.query.filter(
            Station.display_order > station.display_order
        ).order_by(Station.display_order).first()
        
        if next_station:
            # Verwissel de display_order waarden
            temp_order = next_station.display_order
            next_station.display_order = station.display_order
            station.display_order = temp_order
            db.session.commit()
            flash(f'Station "{station.name}" naar beneden verplaatst', 'success')
        else:
            flash(f'Station "{station.name}" staat al helemaal onderaan', 'info')
            
    except Exception as e:
        db.session.rollback()
        logger.error(f"Error moving station down: {e}")
        flash(f'Fout bij het verplaatsen van het station: {str(e)}', 'danger')
    
    return redirect(url_for('station.manage_stations'))
