file_put_contents('/tmp/s3_debug.log', "DEBUG LOG START\n", FILE_APPEND);
<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);
date_default_timezone_set('Europe/Amsterdam');
session_start();

// Configuratie
$dbFile = '/var/private/db/radiologger.db';
$bucket = 'radiologger'; // Wasabi bucketnaam
$zipRemoteFolder = 'zipped_files'; // Map in de bucket voor ZIP-bestanden
$tmpDirBase = '/tmp/ziptemp_'; // Temp-directory voor ZIP-aanmaak
$debugLog = '/tmp/s3_debug.log'; // Debug-logbestand

// Zorg dat de ZIP-selectie bestaat in de sessie
if (!isset($_SESSION['zip_recordings'])) {
    $_SESSION['zip_recordings'] = [];
}

// Hulpfunctie: uitvoer van een shellcommando
function runCommand($cmd) {
    $output = [];
    $returnVar = 0;
    exec($cmd, $output, $returnVar);
    return ['output' => implode("\n", $output), 'return' => $returnVar];
}

// Hulpfunctie: controleer of een S3-object bestaat met AWS CLI  
function s3ObjectExists($bucket, $key) {
    global $debugLog;
    // Stel de AWS_SHARED_CREDENTIALS_FILE in zodat de CLI de credentials gebruikt
    $awsCred = "AWS_SHARED_CREDENTIALS_FILE=/var/private/.aws/credentials";
    // Bouw het commando: de key wordt tussen dubbele aanhalingstekens geplaatst.
    $cmd = $awsCred . " aws s3api head-object --bucket " . escapeshellarg($bucket) . " --key \"" . $key . "\" --endpoint-url https://s3.eu-central-1.wasabisys.com 2>&1";
    $result = runCommand($cmd);
    file_put_contents($debugLog, "Commando: $cmd\nOutput: " . $result['output'] . "\nReturn: " . $result['return'] . "\n\n", FILE_APPEND);
    return ($result['return'] === 0);
}

// Hulpfunctie: controleer of een remote bestand bestaat via HTTP HEAD (voor Dennis)
function remoteFileExists($url) {
    $headers = @get_headers($url);
    if (!$headers) return false;
    return (strpos($headers[0], '200') !== false);
}

// Maak verbinding met de SQLite-database
try {
    $pdo = new PDO('sqlite:' . $dbFile);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Database connectie mislukt: " . $e->getMessage());
}

/***** AJAX HANDLERS *****/
if(isset($_GET['ajax'])) {
    $ajaxAction = $_GET['ajax'];
    header('Content-Type: application/json');
    if ($ajaxAction === 'add_to_zip') {
        $recording = isset($_GET['recording']) ? $_GET['recording'] : '';
        if (!$recording) {
            echo json_encode(["error" => "Geen opname meegegeven."]);
            exit;
        }
        // Als het een Dennis-opname is, download deze eerst
        if (strpos($recording, "dennis/") === 0) {
            $parts = explode('/', $recording);
            if(count($parts) < 4) {
                echo json_encode(["error" => "Ongeldig Dennis pad."]);
                exit;
            }
            $denFolder = $parts[1];
            $date = $parts[2];
            $hour = substr($parts[3], 0, 2);
            $remoteUrl = "https://logger.dennishoogeveenmedia.nl/audio/{$denFolder}/{$denFolder}-{$date}-{$hour}.mp3";
            if (!remoteFileExists($remoteUrl)) {
                echo json_encode(["error" => "Dennis opname niet gevonden op de server."]);
                exit;
            }
            $tempDir = sys_get_temp_dir() . '/dennis_' . uniqid();
            if (!mkdir($tempDir, 0777, true)) {
                echo json_encode(["error" => "Kon tijdelijke map niet aanmaken."]);
                exit;
            }
            $localFile = $tempDir . '/' . basename($recording);
            $downloaded = @copy($remoteUrl, $localFile);
            if (!$downloaded) {
                exec("rm -rf " . escapeshellarg($tempDir));
                echo json_encode(["error" => "Download van Dennis opname mislukt."]);
                exit;
            }
            $recording = $localFile;
        } else {
            // Voor lokale opnames: controleer of het object bestaat in de Wasabi bucket via AWS CLI
            if (!s3ObjectExists($bucket, $recording)) {
                echo json_encode(["error" => "Lokale opname niet gevonden in de bucket."]);
                exit;
            }
        }
        if (!in_array($recording, $_SESSION['zip_recordings'])) {
            $_SESSION['zip_recordings'][] = $recording;
        }
        echo json_encode(["zip_count" => count($_SESSION['zip_recordings'])]);
        exit;
    }
    exit;
}

/***** ZIP DOWNLOAD ACTIE *****/
if(isset($_GET['action']) && $_GET['action'] === 'download_zip') {
    if (count($_SESSION['zip_recordings']) < 2) {
        die("Selecteer minimaal 2 opnames voordat u een ZIP-bestand kunt downloaden.");
    }
    $tmpDir = $tmpDirBase . uniqid();
    if (!mkdir($tmpDir, 0777, true)) {
        die("Kon de tijdelijke map niet aanmaken.");
    }
    foreach ($_SESSION['zip_recordings'] as $path) {
        $filename = basename($path);
        $localFile = $tmpDir . '/' . $filename;
        if (file_exists($path)) {
            // Als het een lokaal (Dennis) bestand betreft
            copy($path, $localFile);
        } else {
            // Voor lokale opnames: download het bestand via AWS CLI.
            // Bouw de S3-URL met de key tussen dubbele quotes.
            $source = "s3://{$bucket}/" . $path;
            $cmd = "AWS_SHARED_CREDENTIALS_FILE=/var/private/.aws/credentials aws s3 cp \"" . $source . "\" " . escapeshellarg($localFile) . " --endpoint-url https://s3.eu-central-1.wasabisys.com";
            $result = runCommand($cmd);
            if ($result['return'] !== 0) {
                exec("rm -rf " . escapeshellarg($tmpDir));
                die("Fout bij downloaden van " . htmlspecialchars($path) . ".");
            }
        }
    }
    $zipFileLocal = $tmpDir . '/recordings_' . date("Ymd_His") . '.zip';
    $zipCmd = "cd " . escapeshellarg($tmpDir) . " && zip -r " . escapeshellarg($zipFileLocal) . " .";
    if (runCommand($zipCmd)['return'] !== 0) {
        exec("rm -rf " . escapeshellarg($tmpDir));
        die("Fout bij aanmaken van de ZIP.");
    }
    $remoteZipPath = $zipRemoteFolder . '/' . basename($zipFileLocal);
    $uploadCmd = "AWS_SHARED_CREDENTIALS_FILE=/var/private/.aws/credentials aws s3 cp " . escapeshellarg($zipFileLocal) . " s3://{$bucket}/" . $remoteZipPath . " --endpoint-url https://s3.eu-central-1.wasabisys.com";
    if (runCommand($uploadCmd)['return'] !== 0) {
        exec("rm -rf " . escapeshellarg($tmpDir));
        die("Fout bij uploaden van de ZIP naar Wasabi.");
    }
    $presignCmd = "AWS_SHARED_CREDENTIALS_FILE=/var/private/.aws/credentials aws s3 presign s3://{$bucket}/" . $remoteZipPath . " --expires-in 3600 --endpoint-url https://s3.eu-central-1.wasabisys.com";
    $zipUrlResult = runCommand($presignCmd);
    if ($zipUrlResult === false || $zipUrlResult['return'] !== 0) {
        exec("rm -rf " . escapeshellarg($tmpDir));
        die("Fout bij genereren van downloadlink voor de ZIP.");
    }
    $zipUrl = trim($zipUrlResult['output']);
    exec("rm -rf " . escapeshellarg($tmpDir));
    $_SESSION['zip_recordings'] = [];
    echo "<h2>ZIP-bestand aangemaakt</h2>";
    echo "<p><a href='" . htmlspecialchars($zipUrl) . "' target='_blank'>Download ZIP-bestand</a></p>";
    echo "<p><a href='list_recordings.php'>Terug naar overzicht</a></p>";
    exit;
}

if(isset($_GET['action']) && $_GET['action'] === 'reset_zip') {
    $_SESSION['zip_recordings'] = [];
    header("Location: list_recordings.php");
    exit;
}

/***** OPBOUW JSON STRUCTUUR (volgens oorspronkelijke script) *****/
// Lokale opnames
$sqlLocal = "SELECT station, date, hour, filepath, program_title
             FROM recordings
             ORDER BY station ASC, date DESC, hour ASC";
$stmtLocal = $pdo->query($sqlLocal);
$rowsLocal = $stmtLocal->fetchAll(PDO::FETCH_ASSOC);

// Dennis-stations
$sqlDennis = "SELECT name, folder FROM dennis WHERE visible_in_logger = 1 ORDER BY name ASC";
$stmtDennis = $pdo->query($sqlDennis);
$rowsDennis = $stmtDennis->fetchAll(PDO::FETCH_ASSOC);

// Bouw gecombineerde structuur
$structure = [];
foreach ($rowsLocal as $row) {
    $station = $row['station'];
    $date    = $row['date'];
    $hour    = $row['hour'];
    $title   = $row['program_title'] ?: '';
    $cloudpath = "opnames/" . $station . "/" . $date . "/" . $hour . ".mp3";
    if (!isset($structure[$station])) {
        $structure[$station] = [];
    }
    if (!isset($structure[$station][$date])) {
        $structure[$station][$date] = [];
    }
    $structure[$station][$date][] = [
        'hour'          => $hour,
        'type'          => 'local',
        'cloudpath'     => $cloudpath,
        'program_title' => $title,
    ];
}
foreach ($rowsDennis as $denSt) {
    $denStationName = $denSt['name'];
    $denFolder      = $denSt['folder'];
    $todayTimestamp = strtotime('today');
    $currentHour = intval(date('H'));
    $currentDate = date('Y-m-d');
    for ($d = 0; $d < 7; $d++) {
        $ts = $todayTimestamp - ($d * 86400);
        $theDate = date('Y-m-d', $ts);
        for ($h = 0; $h < 24; $h++) {
            if ($theDate == $currentDate && $h > $currentHour) {
                continue;
            }
            $hourStr = str_pad($h, 2, '0', STR_PAD_LEFT);
            $cloudpath = "dennis/" . $denFolder . "/" . $theDate . "/" . $hourStr . ".mp3";
            if (!isset($structure[$denStationName])) {
                $structure[$denStationName] = [];
            }
            if (!isset($structure[$denStationName][$theDate])) {
                $structure[$denStationName][$theDate] = [];
            }
            $structure[$denStationName][$theDate][] = [
                'hour'          => $hourStr,
                'type'          => 'dennis',
                'cloudpath'     => $cloudpath,
                'program_title' => '',
            ];
        }
    }
}
$bigData = [];
foreach ($structure as $station => $datesArray) {
    $datesList = [];
    foreach ($datesArray as $date => $recArr) {
        usort($recArr, function($a, $b) {
            return strcmp($a['hour'], $b['hour']);
        });
        $datesList[] = ['date' => $date, 'recordings' => $recArr];
    }
    usort($datesList, function($a, $b) {
        return strcmp($b['date'], $a['date']);
    });
    $bigData[] = ['station' => $station, 'dates' => $datesList];
}
$jsonData = json_encode($bigData, JSON_UNESCAPED_SLASHES);
if ($jsonData === false) {
    die("JSON encoding mislukt: " . json_last_error_msg());
}
?>
<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8">
  <title>Opnames Overzicht</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    select, button { padding: 6px 12px; margin: 5px; font-size: 1em; }
    .button { text-decoration: none; border: 1px solid #333; background-color: #eee; cursor: pointer; }
  </style>
  <script>
    var stationsData = <?php echo $jsonData; ?>;
    window.addEventListener("DOMContentLoaded", function(){
      var storedStation = localStorage.getItem('selectedStation');
      var storedDate = localStorage.getItem('selectedDate');
      var storedHour = localStorage.getItem('selectedHour');
      var stationSelect = document.getElementById("stationSelect");
      var dateSelect = document.getElementById("dateSelect");
      var hourSelect = document.getElementById("hourSelect");
      var openBtn = document.getElementById("openPlayerButton");
      var addZipBtn = document.getElementById("addZipButton");
      stationSelect.innerHTML = "<option value=''>-- Kies een station --</option>";
      stationsData.forEach(function(st) {
         var opt = document.createElement("option");
         opt.value = st.station;
         opt.text = st.station;
         if(storedStation && st.station === storedStation) {
             opt.selected = true;
         }
         stationSelect.add(opt);
      });
      function updateDateDropdown() {
         var stVal = stationSelect.value;
         var stObj = stationsData.find(item => item.station === stVal);
         dateSelect.innerHTML = "";
         if(stObj && stObj.dates.length > 0) {
             stObj.dates.forEach(function(d, index) {
                var opt = document.createElement("option");
                opt.value = d.date;
                opt.text = d.date;
                if((!storedDate && index === 0) || (storedDate && d.date === storedDate)) {
                   opt.selected = true;
                }
                dateSelect.add(opt);
             });
         }
         updateHourDropdown();
      }
      function updateHourDropdown() {
         var stVal = stationSelect.value;
         var dtVal = dateSelect.value;
         var stObj = stationsData.find(item => item.station === stVal);
         hourSelect.innerHTML = "";
         if(stObj) {
             var dtObj = stObj.dates.find(dd => dd.date === dtVal);
             if(dtObj && dtObj.recordings.length > 0) {
                dtObj.recordings.forEach(function(r, index) {
                   var opt = document.createElement("option");
                   opt.value = r.cloudpath;
                   opt.text = r.hour + (r.program_title ? " (" + r.program_title + ")" : "");
                   if((!storedHour && index === 0) || (storedHour && r.cloudpath === storedHour)) {
                      opt.selected = true;
                   }
                   hourSelect.add(opt);
                });
             }
         }
         saveSelection();
         updateButtonState();
      }
      function updateButtonState() {
         openBtn.disabled = (hourSelect.value === "");
         addZipBtn.disabled = (hourSelect.value === "");
      }
      function saveSelection() {
         localStorage.setItem('selectedStation', stationSelect.value);
         localStorage.setItem('selectedDate', dateSelect.value);
         localStorage.setItem('selectedHour', hourSelect.value);
      }
      stationSelect.addEventListener("change", function(){
         saveSelection();
         updateDateDropdown();
      });
      dateSelect.addEventListener("change", function(){
         saveSelection();
         updateHourDropdown();
      });
      hourSelect.addEventListener("change", function(){
         saveSelection();
         updateButtonState();
      });
      updateDateDropdown();
      openBtn.addEventListener("click", function(){
          var cp = hourSelect.value;
          if(cp) {
             window.open("player.php?cloudpath=" + encodeURIComponent(cp), "_blank");
          }
      });
      addZipBtn.addEventListener("click", function(){
          var cp = hourSelect.value;
          if(!cp) return;
          fetch("list_recordings.php?ajax=add_to_zip&recording=" + encodeURIComponent(cp))
             .then(response => response.json())
             .then(data => {
                if(data.error) {
                    alert(data.error);
                } else {
                    document.getElementById("zipCount").textContent = data.zip_count;
                    if(data.zip_count >= 2) {
                        document.getElementById("downloadZipButton").style.display = "inline-block";
                    } else {
                        document.getElementById("downloadZipButton").style.display = "none";
                    }
                }
             });
      });
    });
  </script>
</head>
<body>
<h1>Beschikbare Opnames</h1>
<label for="stationSelect">Station:</label>
<select id="stationSelect"></select>
<br>
<label for="dateSelect">Datum:</label>
<select id="dateSelect"></select>
<br>
<label for="hourSelect">Uur:</label>
<select id="hourSelect"></select>
<br>
<button id="openPlayerButton" class="button" disabled>Open in player</button>
<button id="addZipButton" class="button" disabled>Voeg toe aan .zip</button>
<p>Opnames in ZIP-selectie: <span id="zipCount"><?php echo count($_SESSION['zip_recordings']); ?></span></p>
<a id="downloadZipButton" class="button" href="list_recordings.php?action=download_zip" style="display: <?php echo (count($_SESSION['zip_recordings'])>=2 ? "inline-block" : "none"); ?>;">Download ZIP-bestand</a>
<a class="button" href="list_recordings.php?action=reset_zip">Reset ZIP-selectie</a>
</body>
</html>
