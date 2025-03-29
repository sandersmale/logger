import os
import boto3
import logging
from app import app, db
from models import Recording
from datetime import datetime
from botocore.exceptions import ClientError

logger = logging.getLogger(__name__)

def initialize_s3_client():
    """Initialize the S3 client for Wasabi"""
    return boto3.client(
        's3',
        endpoint_url=app.config['WASABI_ENDPOINT_URL'],
        region_name=app.config['WASABI_REGION'],
        aws_access_key_id=app.config['WASABI_ACCESS_KEY'],
        aws_secret_access_key=app.config['WASABI_SECRET_KEY']
    )

def list_s3_files(prefix=''):
    """List files in the S3 bucket with the given prefix"""
    try:
        s3_client = initialize_s3_client()
        
        # Use paginator to handle large lists
        paginator = s3_client.get_paginator('list_objects_v2')
        result = []
        
        for page in paginator.paginate(Bucket=app.config['WASABI_BUCKET'], Prefix=prefix):
            if 'Contents' in page:
                for obj in page['Contents']:
                    result.append({
                        'key': obj['Key'],
                        'size': obj['Size'],
                        'last_modified': obj['LastModified']
                    })
        
        return result
    
    except Exception as e:
        logger.error(f"Error listing S3 files: {e}")
        return []

def generate_presigned_url(s3_key, expires_in=3600):
    """Generate a presigned URL for an S3 object"""
    try:
        s3_client = initialize_s3_client()
        
        url = s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': app.config['WASABI_BUCKET'], 'Key': s3_key},
            ExpiresIn=expires_in
        )
        
        return url
    
    except Exception as e:
        logger.error(f"Error generating presigned URL for {s3_key}: {e}")
        return None

def upload_file_to_s3(local_path, s3_key):
    """Upload a file to S3"""
    try:
        s3_client = initialize_s3_client()
        
        s3_client.upload_file(local_path, app.config['WASABI_BUCKET'], s3_key)
        logger.info(f"Uploaded {local_path} to s3://{app.config['WASABI_BUCKET']}/{s3_key}")
        
        return True
    
    except Exception as e:
        logger.error(f"Error uploading {local_path} to S3: {e}")
        return False

def delete_file_from_s3(s3_key):
    """Delete a file from S3"""
    try:
        s3_client = initialize_s3_client()
        
        s3_client.delete_object(Bucket=app.config['WASABI_BUCKET'], Key=s3_key)
        logger.info(f"Deleted s3://{app.config['WASABI_BUCKET']}/{s3_key}")
        
        return True
    
    except Exception as e:
        logger.error(f"Error deleting {s3_key} from S3: {e}")
        return False

def file_exists_in_s3(s3_key):
    """Check if a file exists in S3"""
    try:
        s3_client = initialize_s3_client()
        
        s3_client.head_object(Bucket=app.config['WASABI_BUCKET'], Key=s3_key)
        return True
    
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            return False
        else:
            logger.error(f"Error checking if {s3_key} exists in S3: {e}")
            return False
    except Exception as e:
        logger.error(f"Error checking if {s3_key} exists in S3: {e}")
        return False

def count_station_recordings(station_id):
    """Count the number of recordings for a station"""
    try:
        return Recording.query.filter_by(station_id=station_id).count()
    except Exception as e:
        logger.error(f"Error counting recordings for station {station_id}: {e}")
        return 0

def get_station_recording_size(station_id):
    """Get the total size of recordings for a station"""
    try:
        # Get all recordings for this station
        recordings = Recording.query.filter_by(station_id=station_id).all()
        
        # Get file paths
        s3_keys = [rec.filepath for rec in recordings]
        
        # Check size in S3
        total_size = 0
        s3_client = initialize_s3_client()
        
        for key in s3_keys:
            try:
                response = s3_client.head_object(Bucket=app.config['WASABI_BUCKET'], Key=key)
                total_size += response['ContentLength']
            except Exception:
                pass
        
        return total_size
    
    except Exception as e:
        logger.error(f"Error getting recording size for station {station_id}: {e}")
        return 0
