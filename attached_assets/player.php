<?php
require_once '/var/private/auth.php';
/****************************************************************************** 
 * player.php - Player voor lokale & Dennis-opnames
 *
 * Dit script genereert een URL voor een opnamebestand en biedt zowel 
 * streaming als downloadfunctionaliteit (inclusief fragment-download via ffmpeg).
 *
 * Voor lokale opnames (cloudpath begint met "opnames/") wordt een presigned URL 
 * gegenereerd met AWS CLI.
 * Voor Dennis-opnames (cloudpath begint met "dennis/") wordt de URL rechtstreeks 
 * opgebouwd volgens het patroon:
 *   https://logger.dennishoogeveenmedia.nl/audio/{folder}/{folder}-{date}-{hour}.mp3
 *
 * Gebruik:
 *   - GET: cloudpath (bijv. "opnames/NPO Klassiek/2025-02-27/12" of "dennis/nporadio4/2025-02-27/12")
 *   - GET: action=download (om te downloaden, anders streaming)
 *   - Optioneel GET: start en end (in seconden) voor fragment-download
 *   - Optioneel GET: debug=1 (voor debug-output)
 ******************************************************************************/ 

// 1. Error reporting & logging
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', '/var/private/logs/player_errors.log');
date_default_timezone_set('Europe/Amsterdam');

// 2. AWS credentials
putenv('AWS_SHARED_CREDENTIALS_FILE=/var/private/.aws/credentials');

// 3. Configuratievariabelen
$AWS_CLI  = '/usr/local/bin/aws';   // Pas aan indien nodig
$FFMPEG   = '/usr/bin/ffmpeg';       // Pas aan indien nodig
$endpoint = 'https://s3.eu-central-1.wasabisys.com';
$bucket   = 'radiologger';

// 4. Debug flag & hulpfunctie
$debug = (isset($_GET['debug']) && $_GET['debug'] == '1');
function debug_log($msg) {
    global $debug;
    if ($debug) {
        echo "<p><strong>Debug:</strong> " . htmlspecialchars($msg) . "</p>";
    }
    error_log("[player.php] " . $msg);
}

// 5. Verkrijg GET-parameters
$action    = $_GET['action'] ?? '';
$cloudpath = $_GET['cloudpath'] ?? '';
if (!$cloudpath) {
    debug_log("Geen cloudpath opgegeven.");
    die("<p style='color:red;'>Error: 'cloudpath' parameter is required.</p>");
}
debug_log("Ontvangen cloudpath=$cloudpath, action=$action");

// Bepaal of het een Dennis of lokale opname betreft
$isDennis = false;
if (strpos($cloudpath, 'dennis/') === 0) {
    $isDennis = true;
} elseif (strpos($cloudpath, 'opnames/') === 0) {
    $isDennis = false;
} else {
    debug_log("Ongeldige cloudpath-prefix.");
    die("<p style='color:red;'>Error: cloudpath must start with 'opnames/' or 'dennis/'.</p>");
}

// 6. Bouw de uiteindelijke URL ($finalUrl) en bepaal de bestandsnaam ($customFilename)
if ($isDennis) {
    // Verwacht format: "dennis/{folder}/{date}/{hour}.mp3"
    $parts = explode('/', $cloudpath);
    if (count($parts) < 4) {
        debug_log("Ongeldig Dennis cloudpath formaat.");
        die("<p style='color:red;'>Error: Invalid Dennis cloudpath format.</p>");
    }
    $folder = urldecode($parts[1]);
    $date   = $parts[2];
    $hour   = preg_replace('/\.mp3$/i', '', $parts[3]); 
    $finalUrl = "https://logger.dennishoogeveenmedia.nl/audio/{$folder}/{$folder}-{$date}-{$hour}.mp3";
    $customFilename = "{$folder}-{$date}-{$hour}.mp3";
    debug_log("Dennis URL: $finalUrl");
} else {
    // Lokale opnames: verwacht format: "opnames/{station}/{date}/{hour}.mp3"
    if (!preg_match('/\.mp3$/i', $cloudpath)) {
        $cloudpath .= ".mp3";
    }
    $s3Url = sprintf("s3://%s/%s", $bucket, $cloudpath);
    $cmd = sprintf(
        '%s s3 presign %s --endpoint-url %s --expires-in 3600 2>&1',
        escapeshellcmd($AWS_CLI),
        escapeshellarg($s3Url),
        escapeshellarg($endpoint)
    );
    debug_log("Presign cmd (lokale): $cmd");
    $rawOutput = shell_exec($cmd);
    if (!$rawOutput) {
        debug_log("Geen output van AWS CLI bij presign.");
        die("<p style='color:red;'>Error: Could not generate presigned URL for streaming.</p>");
    }
    $finalUrl = trim($rawOutput);
    $parts = explode('/', $cloudpath);
    if (count($parts) >= 4) {
        $station = urldecode($parts[1]);
        $date = $parts[2];
        $file = basename($cloudpath);
        $customFilename = "{$station}-{$date}-{$file}";
    } else {
        $customFilename = basename($cloudpath);
    }
    debug_log("Lokale presigned URL: $finalUrl");
}

// 7. Download modus
if ($action === 'download') {
    if (isset($_GET['start']) && isset($_GET['end']) && $_GET['start'] !== '' && $_GET['end'] !== '') {
        $start = floatval($_GET['start']);
        $end = floatval($_GET['end']);
        if ($end <= $start) {
            debug_log("Ongeldige markers: eindtijd ($end) ≤ begintijd ($start).");
            die("<p style='color:red;'>Error: End marker must be greater than start marker.</p>");
        }
        $duration = $end - $start;
        $customFilename = preg_replace('/\.mp3$/i', '', $customFilename) . "_fragment_{$start}_{$end}.mp3";
        header("Content-Type: audio/mpeg");
        header("Content-Disposition: attachment; filename=\"" . $customFilename . "\"");
        $ffmpegCmd = sprintf(
            '%s -ss %s -i %s -t %s -c copy -f mp3 pipe:1',
            escapeshellcmd($FFMPEG),
            escapeshellarg($start),
            escapeshellarg($finalUrl),
            escapeshellarg($duration)
        );
        debug_log("ffmpeg cmd (fragment): $ffmpegCmd");
        passthru($ffmpegCmd);
        exit;
    } else {
        header("Content-Type: audio/mpeg");
        header("Content-Disposition: attachment; filename=\"" . $customFilename . "\"");
        $ch = curl_init($finalUrl);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_WRITEFUNCTION, function($ch, $data) {
            echo $data;
            flush();
            return strlen($data);
        });
        $result = curl_exec($ch);
        if (curl_errno($ch)) {
            $error = curl_error($ch);
            debug_log("cURL error tijdens download: $error");
            die("<p style='color:red;'>Error: Could not download file (cURL error: $error).</p>");
        }
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($httpCode != 200) {
            debug_log("HTTP code tijdens download: $httpCode");
            die("<p style='color:red;'>Error: Could not download file (HTTP $httpCode).</p>");
        }
        exit;
    }
}

// 8. Streaming modus (default)
?>
<!DOCTYPE html>
<html lang="nl">
<head>
   <meta charset="UTF-8">
   <title>Opname Player</title>
   <style>
     body { font-family: Arial, sans-serif; margin: 20px; }
     /* Verberg standaard audio controls */
     audio::-webkit-media-controls { display: none !important; }
     audio { width: 100%; margin-bottom: 10px; }
     button { margin: 5px; padding: 10px 15px; font-size: 1em; }
     .debug { background-color: #eef; padding: 10px; border: 1px solid #99f; margin-bottom: 10px; }
   </style>
</head>
<body>
<h1>Opname Player</h1>
<?php if ($debug): ?>
<div class="debug">
  <strong>Gebruikte URL voor streaming:</strong><br>
  <?php echo htmlspecialchars($finalUrl); ?>
</div>
<?php endif; ?>
<audio id="audioPlayer" autoplay>
  <source src="<?php echo htmlspecialchars($finalUrl); ?>" type="audio/mpeg">
  Uw browser ondersteunt het audio-element niet.
</audio>
<!-- Aangepaste navigatieknoppen -->
<button id="btnBack120">-2 min</button>
<button id="btnBack15">-15s</button>
<button id="btnPlayPause">Play/Pause</button>
<button id="btnFwd15">+15s</button>
<button id="btnFwd120">+2 min</button>
<!-- Download-formulier met fragment marker knoppen -->
<form method="get" action="player.php" style="display:inline;" id="downloadForm">
   <input type="hidden" name="cloudpath" value="<?php echo htmlspecialchars($cloudpath); ?>">
   <input type="hidden" name="action" value="download">
   <input type="hidden" id="start" name="start" value="">
   <input type="hidden" id="end" name="end" value="">
   <button type="button" id="btnSetStart">Markeer Start</button>
   <button type="button" id="btnSetEnd">Markeer Eind</button>
   <span id="markerDisplay">Start: --:--, Eind: --:--</span>
   <button type="submit">Download Fragment</button>
   <button type="button" id="btnDownloadFull" onclick="document.getElementById('start').value='';document.getElementById('end').value='';document.getElementById('downloadForm').submit();">Download Volledig</button>
</form>
<p><a href="list_recordings.php">Terug naar overzicht</a></p>
<div id="timeIndicator">00:00 / ??</div>
<script>
const audio = document.getElementById("audioPlayer");
const timeIndicator = document.getElementById("timeIndicator");
let isPlaying = false;
audio.addEventListener("timeupdate", () => {
  let cur = formatTime(audio.currentTime);
  let dur = isNaN(audio.duration) ? "??:??" : formatTime(audio.duration);
  timeIndicator.textContent = cur + " / " + dur;
});
audio.addEventListener("play", () => {
  isPlaying = true;
  document.getElementById("btnPlayPause").textContent = "Pause";
});
audio.addEventListener("pause", () => {
  isPlaying = false;
  document.getElementById("btnPlayPause").textContent = "Play";
});
function formatTime(seconds) {
  let m = Math.floor(seconds / 60);
  let s = Math.floor(seconds % 60);
  return String(m).padStart(2, '0') + ":" + String(s).padStart(2, '0');
}
document.getElementById("btnBack120").addEventListener("click", () => {
  audio.currentTime = Math.max(0, audio.currentTime - 120);
});
document.getElementById("btnBack15").addEventListener("click", () => {
  audio.currentTime = Math.max(0, audio.currentTime - 15);
});
document.getElementById("btnPlayPause").addEventListener("click", () => {
  if (!isPlaying) {
    audio.play();
  } else {
    audio.pause();
  }
});
document.getElementById("btnFwd15").addEventListener("click", () => {
  if (!isNaN(audio.duration)) {
    audio.currentTime = Math.min(audio.duration, audio.currentTime + 15);
  }
});
document.getElementById("btnFwd120").addEventListener("click", () => {
  if (!isNaN(audio.duration)) {
    audio.currentTime = Math.min(audio.duration, audio.currentTime + 120);
  }
});
document.getElementById("btnSetStart").addEventListener("click", () => {
    const startTime = audio.currentTime;
    document.getElementById("start").value = startTime;
    updateMarkerDisplay();
});
document.getElementById("btnSetEnd").addEventListener("click", () => {
    const endTime = audio.currentTime;
    document.getElementById("end").value = endTime;
    updateMarkerDisplay();
});
function updateMarkerDisplay() {
    const start = document.getElementById("start").value;
    const end = document.getElementById("end").value;
    document.getElementById("markerDisplay").textContent = "Start: " + (start ? formatTime(start) : "--:--") + ", Eind: " + (end ? formatTime(end) : "--:--");
}
</script>
</body>
</html>
