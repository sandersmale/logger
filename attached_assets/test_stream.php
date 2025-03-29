<?php
// Geen HTML-foutmeldingen
ini_set('display_errors', 0);
error_reporting(E_ALL);

/**
 * Logt berichten naar /var/private/logs/recordings.log.
 */
function log_message($msg) {
    $log_dir = '/var/private/logs/';
    if (!is_dir($log_dir)) {
        mkdir($log_dir, 0777, true);
    }
    $logfile = $log_dir . "recordings.log";
    file_put_contents($logfile, date('[Y-m-d H:i:s] ') . $msg . "\n", FILE_APPEND);
    flush();
}

log_message("========== [test_stream.php] START ==========");
header('Content-Type: application/json');

// 1) Check 'url'
if (!isset($_GET['url']) || empty($_GET['url'])) {
    $msg = "Geen URL opgegeven.";
    log_message("[test_stream.php][ERROR] $msg");
    exit(json_encode(["error" => $msg]));
}

$origUrl = trim($_GET['url']);
log_message("[test_stream.php] Gekregen url=$origUrl");

if (!filter_var($origUrl, FILTER_VALIDATE_URL)) {
    $msg = "Ongeldige URL.";
    log_message("[test_stream.php][ERROR] $msg");
    exit(json_encode(["error" => $msg]));
}

// 2) playlist-check (.m3u8, .m3u, .pls)
$streams = [];
if (preg_match('/\.(m3u8|m3u|pls)$/i', $origUrl)) {
    log_message("[test_stream.php] Lijkt een playlist (.m3u8/.m3u/.pls). We proberen streams te extraheren...");
    $streams = extractStreams($origUrl);
    if (empty($streams)) {
        $msg = "Geen streams gevonden in playlist.";
        log_message("[test_stream.php][ERROR] $msg");
        exit(json_encode(["error" => $msg]));
    }
} else {
    $streams[] = $origUrl;
}
log_message("[test_stream.php] Aantal streams gevonden: " . count($streams));

// 3) Neem de eerste + fixShoutcast
$testUrl = fixShoutcastV1Url($streams[0]);
log_message("[test_stream.php] Eerste kandidaat: $testUrl");

// 4) Probeer reachability+validity, met fallback op flipHttpHttps als 't mislukt
$finalUrl = tryReachAndValidate($testUrl);

if (!$finalUrl) {
    // flip http<->https
    $flip = flipHttpHttps($testUrl);
    if ($flip !== $testUrl) {
        log_message("[test_stream.php] Probeer flipped URL=$flip...");
        $finalUrl = tryReachAndValidate($flip);
    }
}

// Als beide pogingen mislukten:
if (!$finalUrl) {
    $msg = "Geen werkende stream na http(s)-fallback.";
    log_message("[test_stream.php][ERROR] $msg");
    exit(json_encode(["error" => $msg]));
}

// Succes: Retour
$response = [
    "stream_url" => $finalUrl,
    "status"     => "OK"
];
log_message("[test_stream.php] OK, retour: " . json_encode($response));
log_message("========== [test_stream.php] EINDE ==========");
exit(json_encode($response));

/** =================== HELPERFUNCTIES =================== */

/**
 * V1 fix: als URL eindigt op '/', plak ';' eraan (Shoutcast).
 */
function fixShoutcastV1Url($u) {
    if (substr($u, -1) === '/' && substr($u, -1) !== ';') {
        return $u . ';';
    }
    return $u;
}

/**
 * Als .m3u, .m3u8 of .pls, haal stream-URLs eruit.
 */
function extractStreams($url) {
    log_message("[test_stream.php] extractStreams() -> $url");
    $content = @file_get_contents($url);
    if ($content === false) {
        log_message("[test_stream.php] file_get_contents() mislukt, probeer cURL...");
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (compatible; test_stream_httpfix)');
        curl_setopt($ch, CURLOPT_TIMEOUT, 8);
        $content = curl_exec($ch);
        curl_close($ch);
        if ($content === false) {
            log_message("[test_stream.php][ERROR] Kan de playlist niet ophalen.");
            return [];
        }
    }
    log_message("[test_stream.php] extractStreams() snippet: " . substr($content, 0, 200));

    $streams = [];
    if (preg_match('/\.pls$/i', $url)) {
        // PLS
        preg_match_all('/^\s*File\d+\s*=\s*(.+)$/mi', $content, $matches);
        if (!empty($matches[1])) {
            foreach ($matches[1] as $s) {
                $s = trim($s);
                if (!empty($s)) {
                    $streams[] = $s;
                }
            }
        }
    } elseif (preg_match('/\.m3u8$/i', $url) || preg_match('/\.m3u$/i', $url)) {
        // m3u8 / m3u
        $lines = explode("\n", $content);
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || strpos($line, '#') === 0) {
                continue;
            }
            $streams[] = $line;
        }
    }
    return $streams;
}

/**
 * Flip http<->https in de URL. 
 * Als geen van beide substrings worden herkend, return $url ongewijzigd.
 */
function flipHttpHttps($url) {
    if (stripos($url, 'http://') === 0) {
        return 'https://' . substr($url, 7);
    } elseif (stripos($url, 'https://') === 0) {
        return 'http://' . substr($url, 8);
    }
    // Anders niet herkennen
    return $url;
}

/**
 * Probeert 1x: reachability + ffmpeg-validity.
 * Returnt de werkende URL (string) of false bij falen.
 */
function tryReachAndValidate($u) {
    log_message("[test_stream.php] tryReachAndValidate() start met $u");

    // 1) Reachable?
    if (!isStreamReachable($u)) {
        log_message("[test_stream.php] $u is niet reachable.");
        return false;
    }

    // 2) Valid? (ffmpeg)
    if (!isStreamValid($u)) {
        log_message("[test_stream.php] $u is niet valid (ffmpeg).");
        return false;
    }

    // OK
    log_message("[test_stream.php] $u is reachable + valid.");
    return $u;
}

/**
 * Korte GET: we laden max 64KB en stoppen dan.
 * Content-Type moet 'audio' of 'mpegurl'.
 */
function isStreamReachable($streamUrl) {
    log_message("[test_stream.php] isStreamReachable($streamUrl)");
    $ch = curl_init($streamUrl);

    curl_setopt($ch, CURLOPT_RETURNTRANSFER, false); // we gebruiken writefunction
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (compatible; test_stream_httpfix)');
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    curl_setopt($ch, CURLOPT_HEADER, true);

    $maxBytes = 65536;
    $received = 0;
    $stoppedByUs = false;

    curl_setopt($ch, CURLOPT_WRITEFUNCTION, function($ch, $data) use (&$received, $maxBytes, &$stoppedByUs) {
        $chunkSize = strlen($data);
        $received += $chunkSize;
        if ($received >= $maxBytes) {
            $stoppedByUs = true;
            return 0; // => cURL fout "Failure writing..."
        }
        return $chunkSize;
    });

    $ok  = curl_exec($ch);
    $err = curl_error($ch);
    $httpCode    = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $contentType = curl_getinfo($ch, CURLINFO_CONTENT_TYPE);
    curl_close($ch);

    log_message("[test_stream.php] isStreamReachable() code=$httpCode, ct=$contentType, err=$err, bytes=$received, stoppedByUs=".($stoppedByUs?'true':'false'));

    // cURL error
    if (!empty($err)) {
        // Kijken of we het zelf veroorzaakten:
        if ($stoppedByUs && stripos($err, 'Failure writing output to destination') !== false) {
            log_message("[test_stream.php] Bewust gestopt na $maxBytes bytes (geen echte fout).");
        } else {
            // Echte fout
            log_message("[test_stream.php][ERROR] cURL error: $err");
            return false;
        }
    }

    // HTTP 2xx/3xx
    if ($httpCode < 200 || $httpCode >= 400) {
        return false;
    }
    // content-type moet 'audio' of 'mpegurl'
    if ($contentType) {
        $lc = strtolower($contentType);
        if (strpos($lc, 'audio') === false && strpos($lc, 'mpegurl') === false) {
            return false;
        }
    } else {
        return false;
    }

    return true;
}

/**
 * ffmpeg: check of stream in 2s audio produceert.
 */
function isStreamValid($streamUrl) {
    log_message("[test_stream.php] isStreamValid($streamUrl)");
    $cmd = "ffmpeg -user_agent 'Mozilla/5.0 (compatible; test_stream_httpfix)'"
         . " -i " . escapeshellarg($streamUrl)
         . " -t 2 -f null - 2>&1";

    log_message("[test_stream.php] ffmpeg cmd: $cmd");
    $output = shell_exec($cmd);
    log_message("[test_stream.php] ffmpeg output snippet: ".substr($output, 0, 300));

    // Als we "Audio:" of "Output #0" of "Stream mapping" zien, aannemen dat 't audio is
    if (strpos($output, "Stream mapping") !== false ||
        strpos($output, "Output #0") !== false ||
        strpos($output, "Audio:") !== false) {
        return true;
    }
    return false;
}
