import os
import time
import subprocess
import signal
import logging
import boto3
import sqlite3
from app import app, db, scheduler
from models import Station, Recording, ScheduledJob
from datetime import datetime, date, timedelta
import threading
import tempfile
import re

logger = logging.getLogger(__name__)

def start_scheduler(scheduler_instance):
    """Initialize the scheduler with jobs"""
    # Schedule regular jobs
    scheduler_instance.add_job(
        start_scheduled_recordings,
        'cron',
        hour='*',
        minute=0,  # Run at exactly the hour mark
        second=1,  # Slight delay to ensure we're in the new hour
        id='start_scheduled_recordings',
        replace_existing=True
    )
    
    scheduler_instance.add_job(
        upload_and_remove,
        'interval',
        minutes=15,
        id='upload_and_remove',
        replace_existing=True
    )
    
    scheduler_instance.add_job(
        download_omroeplvc,
        'cron',
        hour='*',
        minute=5,  # Run 5 minutes after the hour
        id='download_omroeplvc',
        replace_existing=True
    )
    
    scheduler_instance.add_job(
        cleanup_logs,
        'cron',
        hour=4,
        minute=0,  # Run at 4:00 AM
        id='cleanup_logs',
        replace_existing=True
    )
    
    # Startup check
    scheduler_instance.add_job(
        prep_for_recording,
        'date',
        run_date=datetime.now() + timedelta(seconds=10),
        id='prep_at_startup',
        replace_existing=True
    )

def prep_for_recording():
    """Check if the system is ready for recording"""
    logger.info("🔄 PREP-modus gestart")
    
    # Check disk space
    disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
    disk_free_gb = disk_free / (1024**3)
    
    if disk_free_gb < 2:
        logger.warning(f"⚠️ Weinig schijfruimte: {disk_free_gb:.2f} GB over")
        return {'status': 'error', 'message': 'Onvoldoende schijfruimte'}
    
    # Check ffmpeg
    try:
        result = subprocess.run([app.config['FFMPEG_PATH'], '-version'], 
                              stdout=subprocess.PIPE, 
                              stderr=subprocess.PIPE, 
                              text=True,
                              timeout=5)
        if result.returncode != 0:
            logger.error(f"⚠️ ffmpeg test mislukt: {result.stderr}")
            return {'status': 'error', 'message': 'ffmpeg test mislukt'}
    except Exception as e:
        logger.error(f"⚠️ ffmpeg test exception: {e}")
        return {'status': 'error', 'message': f'ffmpeg test exception: {e}'}
    
    logger.info("✅ PREP voltooid")
    return {'status': 'ok', 'message': 'PREP voltooid'}

def start_scheduled_recordings():
    """Start scheduled and always-on recordings with segmentation"""
    logger.info("⏳ Start geplande en AO opnames")
    
    with app.app_context():
        stations = Station.query.all()
        current_time = datetime.now()
        
        # Get list of running ffmpeg processes
        process_output = subprocess.check_output(["pgrep", "-af", "ffmpeg"]).decode('utf-8')
        process_lines = [line for line in process_output.split('\n') if line.strip()]
        
        for station in stations:
            station_name = station.name
            station_url = station.recording_url
            
            # Determine if station should be recorded
            is_always_on = station.always_on
            has_schedule = (station.schedule_start_date is not None and 
                          station.schedule_end_date is not None)
            in_schedule = False
            
            if has_schedule:
                start_time = datetime.combine(
                    station.schedule_start_date,
                    datetime.strptime(f"{station.schedule_start_hour:02d}:00", "%H:%M").time()
                )
                end_time = datetime.combine(
                    station.schedule_end_date,
                    datetime.strptime(f"{station.schedule_end_hour:02d}:00", "%H:%M").time()
                )
                
                if current_time >= start_time and current_time < end_time:
                    in_schedule = True
            
            should_record = is_always_on or (has_schedule and in_schedule)
            
            if should_record:
                # Check disk space
                disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
                disk_free_gb = disk_free / (1024**3)
                
                if disk_free_gb < 2:
                    logger.warning(f"⚠️ Weinig schijfruimte: {disk_free_gb:.2f} GB. Opname niet gestart voor {station_name}.")
                    continue
                
                # Generate output pattern
                output_pattern = generate_output_pattern(station_name)
                expected_dir = os.path.dirname(output_pattern)
                
                # Check if process is already running for this station
                process_found = False
                processes_to_kill = []
                
                for line in process_lines:
                    if station_url in line:
                        if expected_dir in line:
                            process_found = True
                            break
                        else:
                            # Old process with wrong output dir - kill it
                            parts = line.split(" ", 1)
                            if parts[0].isdigit():
                                processes_to_kill.append(parts[0])
                
                # Kill old processes
                for pid in processes_to_kill:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                        logger.info(f"🛑 Oude opname voor {station_name} (PID {pid}) gestopt.")
                    except Exception as e:
                        logger.error(f"Error killing process {pid}: {e}")
                
                # Start new recording if not already running
                if not process_found:
                    try:
                        # Resolve playlist URL if needed
                        resolved_url = resolve_stream_url(station_url)
                        
                        # Build and execute ffmpeg command
                        ffmpeg_cmd = [
                            app.config['FFMPEG_PATH'],
                            '-i', resolved_url,
                            '-vn',  # No video
                            '-acodec', 'copy',  # Copy audio codec (no transcoding)
                            '-f', 'segment',  # Segment format
                            '-segment_time', '3600',  # 1-hour segments
                            '-reset_timestamps', '1',
                            '-segment_atclocktime', '1',
                            '-strftime', '1',
                            output_pattern
                        ]
                        
                        env = os.environ.copy()
                        env['TZ'] = 'Europe/Amsterdam'
                        
                        process = subprocess.Popen(
                            ffmpeg_cmd,
                            stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL,
                            env=env
                        )
                        
                        logger.info(f"🎤 Opname gestart voor {station_name} (output: {output_pattern}), PID: {process.pid}")
                        
                        # Create or update job record
                        job_type = 'always_on' if is_always_on else 'scheduled'
                        job = ScheduledJob.query.filter_by(
                            station_id=station.id, 
                            job_type=job_type,
                            status='running'
                        ).first()
                        
                        if job:
                            job.start_time = current_time
                        else:
                            job = ScheduledJob(
                                job_id=f"{job_type}_{station.id}_{current_time.strftime('%Y%m%d%H%M%S')}",
                                station_id=station.id,
                                job_type=job_type,
                                start_time=current_time,
                                status='running'
                            )
                            db.session.add(job)
                        
                        db.session.commit()
                    
                    except Exception as e:
                        logger.error(f"Error starting recording for {station_name}: {e}")
            else:
                # Stop any running processes for this station
                stop_recording(station.id)

def start_manual_recording(station_id):
    """Start a manual recording (1 hour) for a station"""
    try:
        with app.app_context():
            station = Station.query.get(station_id)
            if not station:
                return {'success': False, 'error': 'Station not found'}
            
            # Check disk space
            disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
            disk_free_gb = disk_free / (1024**3)
            
            if disk_free_gb < 2:
                logger.warning(f"⚠️ Weinig schijfruimte: {disk_free_gb:.2f} GB. Geen handmatige opname voor {station.name}.")
                return {'success': False, 'error': f'Onvoldoende schijfruimte: {disk_free_gb:.2f} GB'}
            
            # Prepare output path
            current_date = date.today()
            hour_raw = datetime.now().hour
            
            directory = os.path.join(app.config['RECORDINGS_DIR'], station.name, current_date.strftime('%Y-%m-%d'))
            os.makedirs(directory, exist_ok=True)
            
            file_path = os.path.join(directory, f"{hour_raw:02d}.mp3")
            
            # Resolve playlist URL if needed
            resolved_url = resolve_stream_url(station.recording_url)
            
            # Build and execute ffmpeg command
            ffmpeg_cmd = [
                app.config['FFMPEG_PATH'],
                '-i', resolved_url,
                '-vn',  # No video
                '-acodec', 'copy',  # Copy audio codec
                '-t', '3600',  # Record exactly 1 hour
                file_path
            ]
            
            env = os.environ.copy()
            env['TZ'] = 'Europe/Amsterdam'
            
            process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=env
            )
            
            logger.info(f"🎤 Handmatige opname gestart voor {station.name}, file={file_path}, PID: {process.pid}")
            
            # Create recording record
            recording = Recording(
                station_id=station.id,
                date=current_date,
                hour=f"{hour_raw:02d}",
                filepath=f"opnames/{station.name}/{current_date.strftime('%Y-%m-%d')}/{hour_raw:02d}.mp3",
                recording_type='manual'
            )
            
            # Create job record
            job = ScheduledJob(
                job_id=f"manual_{station.id}_{datetime.now().strftime('%Y%m%d%H%M%S')}",
                station_id=station.id,
                job_type='manual',
                start_time=datetime.now(),
                status='running'
            )
            
            db.session.add(recording)
            db.session.add(job)
            db.session.commit()
            
            return {'success': True, 'file': file_path, 'pid': process.pid}
    
    except Exception as e:
        logger.error(f"Error starting manual recording: {e}")
        return {'success': False, 'error': str(e)}

def stop_recording(station_id):
    """Stop all recordings for a station"""
    try:
        with app.app_context():
            station = Station.query.get(station_id)
            if not station:
                return {'success': False, 'error': 'Station not found'}
            
            # Find running processes for this station
            process_output = subprocess.check_output(["pgrep", "-af", "ffmpeg"]).decode('utf-8')
            processes_killed = 0
            
            for line in process_output.split('\n'):
                if station.recording_url in line:
                    parts = line.split(" ", 1)
                    if parts[0].isdigit():
                        try:
                            pid = int(parts[0])
                            os.kill(pid, signal.SIGTERM)
                            processes_killed += 1
                            logger.info(f"🛑 Opname voor {station.name} gestopt (PID: {pid}).")
                        except Exception as e:
                            logger.error(f"Error killing process {pid}: {e}")
            
            # Update job records
            jobs = ScheduledJob.query.filter_by(
                station_id=station.id,
                status='running'
            ).all()
            
            for job in jobs:
                job.status = 'stopped'
                job.end_time = datetime.now()
            
            db.session.commit()
            
            return {'success': True, 'processes_killed': processes_killed}
    
    except Exception as e:
        logger.error(f"Error stopping recording: {e}")
        return {'success': False, 'error': str(e)}

def upload_and_remove():
    """Upload recordings to S3 and remove local files older than retention period"""
    logger.info("⬆️ Starting upload_and_remove task")
    
    try:
        with app.app_context():
            # Initialize S3 client
            s3_client = boto3.client(
                's3',
                endpoint_url=app.config['S3_ENDPOINT'],
                region_name=app.config['S3_REGION']
            )
            
            # 1. Find MP3 files to upload
            mp3_files = []
            for root, _, files in os.walk(app.config['RECORDINGS_DIR']):
                for file in files:
                    if file.endswith('.mp3') and re.match(r'^\d{2}\.mp3$', file):
                        mp3_files.append(os.path.join(root, file))
            
            # 2. Upload each file to S3
            for file_path in mp3_files:
                try:
                    # Extract components from path
                    rel_path = os.path.relpath(file_path, app.config['RECORDINGS_DIR'])
                    parts = rel_path.split(os.sep)
                    
                    if len(parts) >= 3:
                        station_name = parts[0]
                        date_str = parts[1]
                        hour_file = parts[2]
                        
                        # S3 key: opnames/station/date/hour.mp3
                        s3_key = f"opnames/{station_name}/{date_str}/{hour_file}"
                        
                        # Upload file if it doesn't exist or if local file is newer
                        try:
                            s3_client.head_object(Bucket=app.config['S3_BUCKET'], Key=s3_key)
                            # File exists, check if local is newer (modification time)
                            local_mtime = os.path.getmtime(file_path)
                            
                            # Only upload if local file is newer than 60 seconds
                            # This handles the case of ongoing recordings
                            if time.time() - local_mtime > 60:
                                continue
                        
                        except Exception:
                            # File doesn't exist, upload it
                            pass
                        
                        # Upload file
                        s3_client.upload_file(file_path, app.config['S3_BUCKET'], s3_key)
                        logger.info(f"⬆️ Uploaded {file_path} to s3://{app.config['S3_BUCKET']}/{s3_key}")
                        
                        # Add to database if not exists
                        station = Station.query.filter_by(name=station_name).first()
                        if station:
                            hour = hour_file.replace('.mp3', '')
                            recording_date = datetime.strptime(date_str, '%Y-%m-%d').date()
                            
                            recording = Recording.query.filter_by(
                                station_id=station.id,
                                date=recording_date,
                                hour=hour
                            ).first()
                            
                            if not recording:
                                recording = Recording(
                                    station_id=station.id,
                                    date=recording_date,
                                    hour=hour,
                                    filepath=f"opnames/{station_name}/{date_str}/{hour_file}",
                                    recording_type='scheduled',
                                    s3_uploaded=True
                                )
                                db.session.add(recording)
                                db.session.commit()
                            elif not recording.s3_uploaded:
                                recording.s3_uploaded = True
                                db.session.commit()
                
                except Exception as e:
                    logger.error(f"Error uploading {file_path}: {e}")
            
            # 3. List files on S3 and sync with database
            try:
                # Use paginator to handle large lists
                paginator = s3_client.get_paginator('list_objects_v2')
                s3_files = []
                
                for page in paginator.paginate(Bucket=app.config['S3_BUCKET'], Prefix='opnames/'):
                    if 'Contents' in page:
                        for obj in page['Contents']:
                            s3_files.append(obj['Key'])
                
                # Create temporary files for comparison
                with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_remote, \
                    tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_db:
                    
                    # Write S3 files to temp file
                    for s3_path in sorted(s3_files):
                        tmp_remote.write(f"{s3_path}\n")
                    
                    # Write DB records to temp file
                    for rec in Recording.query.all():
                        tmp_db.write(f"{rec.filepath}\n")
                    
                    tmp_remote.flush()
                    tmp_db.flush()
                    
                    # Re-open for reading
                    tmp_remote.close()
                    tmp_db.close()
                    
                    # Use comm to find differences
                    with tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_added, \
                        tempfile.NamedTemporaryFile(mode='w+', delete=False) as tmp_removed:
                        
                        # Find files in S3 but not in DB (to add)
                        subprocess.run(
                            f"comm -13 {tmp_db.name} {tmp_remote.name}",
                            shell=True,
                            stdout=tmp_added,
                            check=True
                        )
                        
                        # Find files in DB but not in S3 (to remove)
                        subprocess.run(
                            f"comm -23 {tmp_db.name} {tmp_remote.name}",
                            shell=True,
                            stdout=tmp_removed,
                            check=True
                        )
                        
                        tmp_added.flush()
                        tmp_removed.flush()
                        
                        # Re-open for reading
                        tmp_added.close()
                        tmp_removed.close()
                        
                        # Process files to add
                        with open(tmp_added.name, 'r') as f:
                            for s3_path in f:
                                s3_path = s3_path.strip()
                                if not s3_path:
                                    continue
                                
                                # Parse path: opnames/station/date/hour.mp3
                                parts = s3_path.split('/')
                                if len(parts) >= 4:
                                    station_name = parts[1]
                                    date_str = parts[2]
                                    hour_file = parts[3]
                                    
                                    station = Station.query.filter_by(name=station_name).first()
                                    if station:
                                        hour = hour_file.replace('.mp3', '')
                                        
                                        try:
                                            recording_date = datetime.strptime(date_str, '%Y-%m-%d').date()
                                            
                                            recording = Recording(
                                                station_id=station.id,
                                                date=recording_date,
                                                hour=hour,
                                                filepath=s3_path,
                                                recording_type='scheduled',
                                                s3_uploaded=True
                                            )
                                            db.session.add(recording)
                                            logger.info(f"Added {s3_path} to database")
                                        except ValueError:
                                            logger.error(f"Invalid date format in {s3_path}")
                        
                        # Process files to remove
                        with open(tmp_removed.name, 'r') as f:
                            for db_path in f:
                                db_path = db_path.strip()
                                if not db_path:
                                    continue
                                
                                # Find and delete the recording
                                recording = Recording.query.filter_by(filepath=db_path).first()
                                if recording:
                                    db.session.delete(recording)
                                    logger.info(f"Removed {db_path} from database")
                        
                        db.session.commit()
                
                # Delete temporary files
                for tmp_file in [tmp_remote.name, tmp_db.name, tmp_added.name, tmp_removed.name]:
                    try:
                        os.unlink(tmp_file)
                    except Exception:
                        pass
            
            except Exception as e:
                logger.error(f"Error synchronizing database with S3: {e}")
            
            # 4. Remove local files older than retention period
            retention_hours = app.config.get('LOCAL_FILE_RETENTION', 2)
            cutoff_time = time.time() - (retention_hours * 3600)
            
            removed_count = 0
            for file_path in mp3_files:
                try:
                    if os.path.getmtime(file_path) < cutoff_time:
                        os.remove(file_path)
                        logger.info(f"Removed old local file: {file_path}")
                        removed_count += 1
                except Exception as e:
                    logger.error(f"Error removing old file {file_path}: {e}")
            
            logger.info(f"🧹 Removed {removed_count} local files older than {retention_hours} hours")
    
    except Exception as e:
        logger.error(f"Error in upload_and_remove task: {e}")

def download_omroeplvc():
    """Download recordings from Omroep Land van Cuijk"""
    logger.info("⬇️ Starting Omroep LvC download task")
    
    try:
        # Determine time to download
        current_minute = datetime.now().minute
        if current_minute < 5:
            # Use previous hour
            target_hour = (datetime.now() - timedelta(hours=1)).hour
            target_date = (datetime.now() - timedelta(hours=1)).date()
        else:
            # Use current hour
            target_hour = datetime.now().hour
            target_date = date.today()
        
        # Determine day abbreviation (ma, di, wo, do, vr, za, zo)
        day_names = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo']
        day_abbr = day_names[target_date.weekday()]
        
        # Build the URL
        file_name = f"{day_abbr}{target_hour:02d}.mp3"
        remote_url = f"{app.config['OMROEP_LVC_URL']}{file_name}"
        
        logger.info(f"⬇️ Trying to download: {remote_url}")
        
        # Local path
        local_dir = os.path.join(app.config['RECORDINGS_DIR'], 'omroep land van cuijk', target_date.strftime('%Y-%m-%d'))
        os.makedirs(local_dir, exist_ok=True)
        local_file = os.path.join(local_dir, f"{target_hour:02d}.mp3")
        
        # Download the file
        response = requests.get(remote_url, stream=True)
        if response.status_code != 200:
            logger.error(f"⚠️ Download failed with status code {response.status_code}")
            return
        
        # Check if response is HTML (error page)
        content_type = response.headers.get('content-type', '')
        if 'text/html' in content_type:
            logger.warning("⚠️ Received HTML instead of audio file - program might not be available")
            return
        
        # Save the file
        with open(local_file, 'wb') as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
        
        logger.info(f"✅ Download successful: {local_file}")
        
        # Add to database
        with app.app_context():
            # Find or create station
            station = Station.query.filter_by(name='omroep land van cuijk').first()
            if not station:
                station = Station(
                    name='omroep land van cuijk',
                    recording_url=app.config['OMROEP_LVC_URL'],
                    always_on=False
                )
                db.session.add(station)
                db.session.commit()
            
            # Add recording if it doesn't exist
            recording = Recording.query.filter_by(
                station_id=station.id,
                date=target_date,
                hour=f"{target_hour:02d}"
            ).first()
            
            if not recording:
                recording = Recording(
                    station_id=station.id,
                    date=target_date,
                    hour=f"{target_hour:02d}",
                    filepath=f"opnames/omroep land van cuijk/{target_date.strftime('%Y-%m-%d')}/{target_hour:02d}.mp3",
                    recording_type='scheduled'
                )
                db.session.add(recording)
                db.session.commit()
                logger.info(f"✅ Added recording to database: {recording.filepath}")
    
    except Exception as e:
        logger.error(f"Error downloading Omroep LvC: {e}")

def cleanup_logs():
    """Clean up log files"""
    logger.info("🧹 Starting log cleanup task")
    
    try:
        # Clear main log file
        log_file = os.path.join(app.config['LOGS_DIR'], 'radiologger.log')
        with open(log_file, 'w') as f:
            f.write(f"Log cleared at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        
        logger.info(f"✅ Cleared log file: {log_file}")
    
    except Exception as e:
        logger.error(f"Error cleaning up logs: {e}")

def resolve_stream_url(url):
    """Resolve playlist URLs and handle Shoutcast V1 URLs"""
    if url.endswith('/') and not url.endswith(';'):
        url = url + ';'  # Fix for Shoutcast V1
    
    # TODO: Implement playlist resolution if needed
    
    return url

def generate_output_pattern(station_name):
    """Generate the output pattern for ffmpeg segmentation"""
    # Format: /var/private/opnames/StationName/YYYY-MM-DD/%H.mp3
    
    # For 00:00, use today's date; for all other hours, use the date from 1 hour ago
    current_hour = datetime.now().hour
    if current_hour == 0:
        target_date = date.today()
    else:
        target_date = (datetime.now() - timedelta(hours=1)).date()
    
    directory = os.path.join(
        app.config['RECORDINGS_DIR'],
        station_name,
        target_date.strftime('%Y-%m-%d')
    )
    
    os.makedirs(directory, exist_ok=True)
    return os.path.join(directory, '%H.mp3')
