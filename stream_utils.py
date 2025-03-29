import re
import logging
import requests
import subprocess
import tempfile
from urllib.parse import urlparse
from app import app

logger = logging.getLogger(__name__)

def test_stream(url):
    """
    Test a stream URL for validity
    
    1. Check if the URL is reachable
    2. Check if it's a playlist and extract streams
    3. Validate with ffmpeg
    4. Try HTTP/HTTPS fallback if needed
    
    Returns:
        dict: {'success': bool, 'stream_url': str, 'error': str}
    """
    logger.info(f"[test_stream] Starting test for URL: {url}")
    
    # Basic URL validation
    if not url:
        return {'success': False, 'error': 'Geen URL opgegeven'}
    
    try:
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            return {'success': False, 'error': 'Ongeldige URL'}
    except Exception:
        return {'success': False, 'error': 'Ongeldige URL'}
    
    # Check for playlist
    streams = []
    if re.search(r'\.(m3u8|m3u|pls)$', url, re.IGNORECASE):
        logger.info(f"[test_stream] URL appears to be a playlist: {url}")
        streams = extract_streams(url)
        if not streams:
            return {'success': False, 'error': 'Geen streams gevonden in playlist'}
    else:
        streams = [url]
    
    logger.info(f"[test_stream] Found {len(streams)} candidate stream(s)")
    
    # Test the first stream
    test_url = fix_shoutcast_v1_url(streams[0])
    logger.info(f"[test_stream] Testing first candidate: {test_url}")
    
    # Try to reach and validate the stream
    final_url = try_reach_and_validate(test_url)
    
    if not final_url:
        # Try HTTP/HTTPS fallback
        flip_url = flip_http_https(test_url)
        if flip_url != test_url:
            logger.info(f"[test_stream] Trying flipped URL: {flip_url}")
            final_url = try_reach_and_validate(flip_url)
    
    if not final_url:
        return {'success': False, 'error': 'Geen werkende stream na http(s)-fallback'}
    
    logger.info(f"[test_stream] Success! Working URL: {final_url}")
    return {'success': True, 'stream_url': final_url}

def fix_shoutcast_v1_url(url):
    """Fix Shoutcast V1 URLs by adding ; at the end if needed"""
    if url.endswith('/') and not url.endswith(';'):
        return url + ';'
    return url

def extract_streams(url):
    """Extract stream URLs from playlist files (m3u, m3u8, pls)"""
    try:
        # Try to download the playlist
        response = requests.get(url, timeout=10, headers={
            'User-Agent': 'Mozilla/5.0 (compatible; RadioLogger/1.0)'
        })
        
        if response.status_code != 200:
            logger.error(f"[extract_streams] Failed to download playlist: HTTP {response.status_code}")
            return []
        
        content = response.text
        streams = []
        
        # Parse based on file type
        if re.search(r'\.pls$', url, re.IGNORECASE):
            # PLS format
            matches = re.findall(r'^\s*File\d+\s*=\s*(.+)$', content, re.MULTILINE | re.IGNORECASE)
            for match in matches:
                streams.append(match.strip())
        
        elif re.search(r'\.(m3u8|m3u)$', url, re.IGNORECASE):
            # M3U/M3U8 format
            lines = content.splitlines()
            for line in lines:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                streams.append(line)
        
        return streams
    
    except Exception as e:
        logger.error(f"[extract_streams] Error: {str(e)}")
        return []

def flip_http_https(url):
    """Flip between HTTP and HTTPS in a URL"""
    if url.startswith('http://'):
        return 'https://' + url[7:]
    elif url.startswith('https://'):
        return 'http://' + url[8:]
    return url

def try_reach_and_validate(url):
    """Try to reach a URL and validate it as an audio stream"""
    # 1. Check if reachable
    if not is_stream_reachable(url):
        logger.info(f"[try_reach_and_validate] URL not reachable: {url}")
        return None
    
    # 2. Validate with ffmpeg
    if not is_stream_valid(url):
        logger.info(f"[try_reach_and_validate] URL not valid (ffmpeg): {url}")
        return None
    
    # Success!
    return url

def is_stream_reachable(url):
    """Check if a stream URL is reachable"""
    try:
        response = requests.head(url, timeout=10, allow_redirects=True, headers={
            'User-Agent': 'Mozilla/5.0 (compatible; RadioLogger/1.0)'
        })
        
        # Check HTTP status
        if response.status_code < 200 or response.status_code >= 400:
            logger.info(f"[is_stream_reachable] Bad HTTP status: {response.status_code}")
            return False
        
        # Check content type
        content_type = response.headers.get('Content-Type', '').lower()
        if 'audio' not in content_type and 'mpegurl' not in content_type:
            # Try a GET request with limited data to check content type
            get_response = requests.get(url, timeout=10, stream=True, headers={
                'User-Agent': 'Mozilla/5.0 (compatible; RadioLogger/1.0)'
            })
            
            # Read a small chunk
            next(get_response.iter_content(chunk_size=1024), None)
            
            content_type = get_response.headers.get('Content-Type', '').lower()
            get_response.close()
            
            if 'audio' not in content_type and 'mpegurl' not in content_type:
                logger.info(f"[is_stream_reachable] Unexpected content type: {content_type}")
                return False
        
        return True
    
    except Exception as e:
        logger.error(f"[is_stream_reachable] Error: {str(e)}")
        return False

def is_stream_valid(url):
    """Validate a stream URL using ffmpeg"""
    try:
        cmd = [
            app.config['FFMPEG_PATH'],
            '-user_agent', 'Mozilla/5.0 (compatible; RadioLogger/1.0)',
            '-i', url,
            '-t', '2',  # Try to get 2 seconds
            '-f', 'null',
            '-'
        ]
        
        process = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        
        output = process.stderr  # ffmpeg outputs to stderr
        
        # Look for indicators that this is an audio stream
        if ('Stream mapping' in output or
            'Output #0' in output or
            'Audio:' in output):
            return True
        
        logger.info(f"[is_stream_valid] ffmpeg output: {output[:200]}")
        return False
    
    except subprocess.TimeoutExpired:
        logger.error("[is_stream_valid] ffmpeg timeout")
        return False
    except Exception as e:
        logger.error(f"[is_stream_valid] Error: {str(e)}")
        return False
