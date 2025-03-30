from app import app, scheduler, db
from models import Station, Recording, ScheduledJob, DennisStation
from datetime import datetime, date, timedelta
from flask import url_for
import logging
import os
import subprocess
import signal
import requests
import tempfile
import re
import boto3
from botocore.exceptions import ClientError
import time

logger = logging.getLogger(__name__)

def initialize_scheduler():
    """Set up scheduler jobs"""
    with app.app_context():
        # Clear any existing scheduled tasks
        scheduler.remove_all_jobs()

        # Add scheduler jobs
        scheduler.add_job(
            check_scheduled_recordings,
            'interval',
            minutes=1,
            id='check_scheduled',
            replace_existing=True
        )
        
        scheduler.add_job(
            hourly_check,
            'cron',
            hour='*',
            minute=0,
            second=0,  # Exact op het hele uur (XX:00:00)
            id='hourly_check',
            replace_existing=True
        )
        
        scheduler.add_job(
            upload_to_wasabi,
            'interval',
            minutes=15,
            id='upload_to_wasabi',
            replace_existing=True
        )
        
        scheduler.add_job(
            download_omroeplvc,
            'cron',
            hour='*',
            minute=8,  # Run at 8 minutes past the hour to match the original shell script
            id='download_omroeplvc',
            replace_existing=True
        )
        
        scheduler.add_job(
            clean_logs,
            'cron',
            hour=4,
            minute=0,
            id='clean_logs',
            replace_existing=True
        )
        
        # Initial status check
        check_running_recordings()

def check_scheduled_recordings():
    """Check and manage scheduled recordings"""
    with app.app_context():
        try:
            logger.debug("Checking scheduled recordings")
            
            # Get all stations
            stations = Station.query.all()
            now = datetime.now()
            
            for station in stations:
                # Check if station should be recorded
                should_record = False
                
                # Always-on stations
                if station.always_on:
                    should_record = True
                
                # Scheduled stations
                elif station.schedule_start_date and station.schedule_end_date:
                    start_time = datetime.combine(
                        station.schedule_start_date,
                        datetime.strptime(f"{station.schedule_start_hour:02d}:00", "%H:%M").time()
                    )
                    end_time = datetime.combine(
                        station.schedule_end_date,
                        datetime.strptime(f"{station.schedule_end_hour:02d}:00", "%H:%M").time()
                    )
                    if now >= start_time and now < end_time:
                        should_record = True
                
                # Get running process info for this station
                process_info = find_recording_process(station.recording_url)
                is_running = process_info is not None
                
                if should_record and not is_running:
                    # Start recording
                    start_recording(station)
                elif not should_record and is_running:
                    # Stop recording
                    stop_recording(process_info['pid'])
        
        except Exception as e:
            logger.error(f"Error in check_scheduled_recordings: {e}")

def hourly_check():
    """Run at the top of each hour to ensure proper segments and clean up"""
    with app.app_context():
        try:
            logger.info("Running hourly check")
            
            # Restart all always-on recordings to ensure proper hourly segments
            stations = Station.query.filter_by(always_on=True).all()
            
            for station in stations:
                process_info = find_recording_process(station.recording_url)
                if process_info:
                    # Stop and restart the recording
                    logger.info(f"Restarting always-on recording for {station.name}")
                    stop_recording(process_info['pid'])
                    start_recording(station)
            
            # Also check scheduled recordings
            check_scheduled_recordings()
            
        except Exception as e:
            logger.error(f"Error in hourly_check: {e}")

def find_recording_process(stream_url):
    """Find ffmpeg process for a given stream URL"""
    try:
        output = subprocess.check_output(["pgrep", "-af", "ffmpeg"]).decode('utf-8')
        
        for line in output.splitlines():
            if stream_url in line:
                parts = line.split(" ", 1)
                if len(parts) >= 2:
                    pid = int(parts[0])
                    command = parts[1]
                    
                    # Extract output path if available
                    # Zoek naar het outputpad in het ffmpeg commando
                    recordings_dir = app.config['RECORDINGS_DIR']
                    output_match = re.search(fr'({re.escape(recordings_dir)}/[^\s]+)', command)
                    output_path = output_match.group(1) if output_match else None
                    
                    return {
                        'pid': pid,
                        'command': command,
                        'output_path': output_path
                    }
        
        return None
    
    except subprocess.CalledProcessError:
        # No ffmpeg processes running
        return None
    
    except Exception as e:
        logger.error(f"Error finding recording process: {e}")
        return None

def start_recording(station):
    """Start a recording for a station"""
    try:
        logger.info(f"Starting recording for {station.name}")
        
        # Check disk space
        disk_free = os.statvfs(app.config['RECORDINGS_DIR']).f_bfree * os.statvfs(app.config['RECORDINGS_DIR']).f_frsize
        disk_free_gb = disk_free / (1024**3)
        
        if disk_free_gb < 2:
            logger.warning(f"Insufficient disk space ({disk_free_gb:.2f} GB), not starting recording for {station.name}")
            return False
        
        # Generate output path
        output_pattern = generate_output_path(station.name)
        
        # Build ffmpeg command
        ffmpeg_cmd = [
            app.config['FFMPEG_PATH'],
            '-i', station.recording_url,
            '-vn',  # No video
            '-acodec', 'copy',  # Copy audio codec (no transcoding)
            '-f', 'segment',  # Segment format
            '-segment_time', '3600',  # 1-hour segments
            '-reset_timestamps', '1',
            '-segment_atclocktime', '1',
            '-strftime', '1',
            output_pattern
        ]
        
        # Set environment variables
        env = os.environ.copy()
        env['TZ'] = 'Europe/Amsterdam'
        
        # Start the process
        process = subprocess.Popen(
            ffmpeg_cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env
        )
        
        logger.info(f"Started recording for {station.name} (PID: {process.pid})")
        
        # Create job record
        job_type = 'always_on' if station.always_on else 'scheduled'
        job = ScheduledJob(
            job_id=f"{job_type}_{station.id}_{datetime.now().strftime('%Y%m%d%H%M%S')}",
            station_id=station.id,
            job_type=job_type,
            start_time=datetime.now(),
            status='running'
        )
        
        db.session.add(job)
        db.session.commit()
        
        return True
    
    except Exception as e:
        logger.error(f"Error starting recording for {station.name}: {e}")
        return False

def stop_recording(pid):
    """Stop a recording process by PID"""
    try:
        logger.info(f"Stopping recording with PID {pid}")
        
        # Send SIGTERM to the process
        os.kill(pid, signal.SIGTERM)
        
        # Update any job records
        jobs = ScheduledJob.query.filter_by(status='running').all()
        for job in jobs:
            # Find the process info for this station
            station = Station.query.get(job.station_id)
            if station:
                process_info = find_recording_process(station.recording_url)
                if not process_info:
                    job.status = 'stopped'
                    job.end_time = datetime.now()
        
        db.session.commit()
        
        return True
    
    except Exception as e:
        logger.error(f"Error stopping recording (PID {pid}): {e}")
        return False

def check_running_recordings():
    """Check which recordings are currently running and update job status"""
    with app.app_context():
        try:
            logger.info("Checking running recordings")
            
            # Get all stations
            stations = Station.query.all()
            
            # Reset status for all running jobs
            jobs = ScheduledJob.query.filter_by(status='running').all()
            for job in jobs:
                job.status = 'unknown'
            
            # Check each station
            for station in stations:
                process_info = find_recording_process(station.recording_url)
                
                if process_info:
                    # Recording is running
                    job = ScheduledJob.query.filter_by(
                        station_id=station.id,
                        status='unknown'
                    ).first()
                    
                    if job:
                        job.status = 'running'
                    else:
                        # Create a new job record
                        job_type = 'always_on' if station.always_on else 'scheduled'
                        job = ScheduledJob(
                            job_id=f"{job_type}_{station.id}_{datetime.now().strftime('%Y%m%d%H%M%S')}",
                            station_id=station.id,
                            job_type=job_type,
                            start_time=datetime.now(),
                            status='running'
                        )
                        db.session.add(job)
            
            # Any remaining 'unknown' jobs are not running
            for job in ScheduledJob.query.filter_by(status='unknown').all():
                job.status = 'stopped'
                job.end_time = datetime.now()
            
            db.session.commit()
            
        except Exception as e:
            logger.error(f"Error checking running recordings: {e}")

def upload_to_wasabi():
    """Upload recordings to Wasabi S3 and clean up local files"""
    with app.app_context():
        try:
            logger.info("Starting upload to Wasabi")
            
            # Initialize S3 client
            s3_client = boto3.client(
                's3',
                endpoint_url=app.config['S3_ENDPOINT'],
                region_name=app.config['S3_REGION']
            )
            
            # Find MP3 files to upload
            mp3_files = []
            for root, _, files in os.walk(app.config['RECORDINGS_DIR']):
                for file in files:
                    if file.endswith('.mp3') and re.match(r'^\d{2}\.mp3$', file):
                        mp3_files.append(os.path.join(root, file))
            
            logger.info(f"Found {len(mp3_files)} MP3 files to process")
            
            # Upload each file
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
                        
                        # Check if file exists in S3
                        try:
                            s3_client.head_object(Bucket=app.config['S3_BUCKET'], Key=s3_key)
                            # File exists, check if local is newer
                            local_mtime = os.path.getmtime(file_path)
                            
                            # Only upload if local file is newer than 60 seconds
                            # This handles the case of ongoing recordings
                            if time.time() - local_mtime > 60:
                                continue
                        
                        except ClientError:
                            # File doesn't exist, upload it
                            pass
                        
                        # Upload file
                        logger.info(f"Uploading {file_path} to S3")
                        s3_client.upload_file(file_path, app.config['S3_BUCKET'], s3_key)
                        
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
                            elif not recording.s3_uploaded:
                                recording.s3_uploaded = True
                            
                            db.session.commit()
                
                except Exception as e:
                    logger.error(f"Error processing {file_path}: {e}")
            
            # Sync database with S3
            try:
                sync_database_with_s3(s3_client)
            except Exception as e:
                logger.error(f"Error syncing database with S3: {e}")
            
            # Clean up old local files
            cleanup_local_files()
            
        except Exception as e:
            logger.error(f"Error in upload_to_wasabi: {e}")

def sync_database_with_s3(s3_client):
    """Synchronize database records with files in S3"""
    logger.info("Syncing database with S3")
    
    # Get all S3 files
    paginator = s3_client.get_paginator('list_objects_v2')
    s3_files = []
    
    for page in paginator.paginate(Bucket=app.config['S3_BUCKET'], Prefix='opnames/'):
        if 'Contents' in page:
            for obj in page['Contents']:
                s3_files.append(obj['Key'])
    
    logger.info(f"Found {len(s3_files)} files in S3")
    
    # Get all recordings in database
    db_records = Recording.query.all()
    db_filepaths = [rec.filepath for rec in db_records]
    
    logger.info(f"Found {len(db_records)} records in database")
    
    # Create temporary files for comparison
    with tempfile.NamedTemporaryFile(mode='w+') as s3_file, \
         tempfile.NamedTemporaryFile(mode='w+') as db_file:
        
        # Write S3 files to temp file
        for file_path in sorted(s3_files):
            s3_file.write(f"{file_path}\n")
        
        # Write DB records to temp file
        for file_path in sorted(db_filepaths):
            db_file.write(f"{file_path}\n")
        
        s3_file.flush()
        db_file.flush()
        
        # Create temp files for differences
        with tempfile.NamedTemporaryFile(mode='w+') as to_add, \
             tempfile.NamedTemporaryFile(mode='w+') as to_remove:
            
            # Find files in S3 but not in DB
            subprocess.run(
                f"comm -13 {db_file.name} {s3_file.name}",
                shell=True,
                stdout=to_add,
                stderr=subprocess.PIPE,
                check=True
            )
            
            # Find files in DB but not in S3
            subprocess.run(
                f"comm -23 {db_file.name} {s3_file.name}",
                shell=True,
                stdout=to_remove,
                stderr=subprocess.PIPE,
                check=True
            )
            
            to_add.flush()
            to_remove.flush()
            
            # Process files to add
            to_add.seek(0)
            for line in to_add:
                s3_path = line.strip()
                if not s3_path:
                    continue
                
                # Parse path: opnames/station/date/hour.mp3
                parts = s3_path.split('/')
                if len(parts) >= 4:
                    try:
                        station_name = parts[1]
                        date_str = parts[2]
                        hour_file = parts[3]
                        
                        station = Station.query.filter_by(name=station_name).first()
                        if station:
                            hour = hour_file.replace('.mp3', '')
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
                            logger.info(f"Added record for {s3_path}")
                    except Exception as e:
                        logger.error(f"Error adding record for {s3_path}: {e}")
            
            # Process files to remove
            to_remove.seek(0)
            for line in to_remove:
                db_path = line.strip()
                if not db_path:
                    continue
                
                try:
                    recording = Recording.query.filter_by(filepath=db_path).first()
                    if recording:
                        db.session.delete(recording)
                        logger.info(f"Removed record for {db_path}")
                except Exception as e:
                    logger.error(f"Error removing record for {db_path}: {e}")
            
            db.session.commit()

def cleanup_local_files():
    """Remove local files older than the retention period"""
    try:
        retention_hours = app.config.get('LOCAL_FILE_RETENTION', 2)
        cutoff_time = time.time() - (retention_hours * 3600)
        
        removed_count = 0
        
        for root, _, files in os.walk(app.config['RECORDINGS_DIR']):
            for file in files:
                if file.endswith('.mp3'):
                    file_path = os.path.join(root, file)
                    try:
                        if os.path.getmtime(file_path) < cutoff_time:
                            os.remove(file_path)
                            removed_count += 1
                    except Exception as e:
                        logger.error(f"Error removing {file_path}: {e}")
        
        logger.info(f"Removed {removed_count} files older than {retention_hours} hours")
    
    except Exception as e:
        logger.error(f"Error in cleanup_local_files: {e}")

def download_omroeplvc():
    """Download recordings from Omroep Land van Cuijk
    
    This task runs 8 minutes after each hour to download the previous hour's recording
    from Omroep Land van Cuijk's archive. The 8-minute delay is required to ensure the
    recording is available in their archive system after broadcast completion.
    """
    with app.app_context():
        try:
            logger.info("⬇️ Starting Omroep LvC download task")
            
            # Current time
            now = datetime.now()
            current_minute = now.minute
            
            # Log current timing
            if current_minute < 8 or current_minute > 11:
                logger.info(f"⬇️ Current minute is {current_minute}, should be around 8 minutes after the hour for optimal download. Continuing anyway.")
            
            # Always target the previous hour for the scheduled task
            # This ensures we get the complete file after it's fully saved
            target_hour = (now - timedelta(hours=1)).hour
            target_date = (now - timedelta(hours=1)).date()
            
            # Determine day abbreviation (ma, di, wo, do, vr, za, zo)
            day_names = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo']
            day_abbr = day_names[target_date.weekday()]
            
            # Build the URL
            file_name = f"{day_abbr}{target_hour:02d}.mp3"
            remote_url = f"{app.config['OMROEP_LVC_URL']}{file_name}"
            
            logger.info(f"Downloading from: {remote_url}")
            
            # Local path
            local_dir = os.path.join(app.config['RECORDINGS_DIR'], 'omroep land van cuijk', target_date.strftime('%Y-%m-%d'))
            os.makedirs(local_dir, exist_ok=True)
            local_file = os.path.join(local_dir, f"{target_hour:02d}.mp3")
            
            # Download the file
            response = requests.get(remote_url, stream=True)
            if response.status_code != 200:
                logger.error(f"Download failed with status code {response.status_code}")
                return
            
            # Check if response is HTML (error page)
            content_type = response.headers.get('content-type', '')
            if 'text/html' in content_type:
                logger.warning("Received HTML instead of audio file - program might not be available")
                return
            
            # Save the file
            with open(local_file, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    f.write(chunk)
            
            logger.info(f"Download successful: {local_file}")
            
            # Add to database
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
        
        except Exception as e:
            logger.error(f"Error downloading Omroep LvC: {e}")

def clean_logs():
    """Clean up log files"""
    try:
        logger.info("Cleaning up logs")
        
        # Clear main log file
        log_file = os.path.join(app.config['LOGS_DIR'], 'radiologger.log')
        with open(log_file, 'w') as f:
            f.write(f"Log cleared at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        
        logger.info(f"Cleared log file: {log_file}")
    
    except Exception as e:
        logger.error(f"Error cleaning up logs: {e}")

def generate_output_path(station_name):
    """Generate output path for ffmpeg recording"""
    # Format: {RECORDINGS_DIR}/StationName/YYYY-MM-DD/%H.mp3
    
    # For 00:00, use today's date; for all other hours, use date from 1 hour ago
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

if __name__ == "__main__":
    # This can be used to test the scheduler functions independently
    with app.app_context():
        print("Testing scheduler functions...")
        check_scheduled_recordings()
