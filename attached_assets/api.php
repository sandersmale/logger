<?php
date_default_timezone_set('Europe/Amsterdam');
// Converteer CLI-argumenten naar $_GET-parameters indien nodig
if (PHP_SAPI === 'cli') {
    if (isset($_SERVER['QUERY_STRING'])) {
        parse_str($_SERVER['QUERY_STRING'], $_GET);
    } elseif (isset($argv) && count($argv) > 1) {
        parse_str(implode('&', array_slice($argv, 1)), $_GET);
    }
}

/**
 * API voor Radiologger met SQLite-database.
 * Ondersteunde acties:
 *   - prep              : Controleert de beschikbare schijfruimte.
 *   - start_scheduled   : Start alle Always-On en geplande opnames met segmentatie.
 *   - start_manual      : Start een handmatige opname (1 uur) voor een geselecteerd station.
 *   - stop_all          : Stopt alle lopende ffmpeg-opnames.
 *   - view_logs         : Toont de inhoud van het logbestand.
 *
 * Er wordt geen gebruik meer gemaakt van het .json-bestand.
 */

// Geen header('Content-Type: application/json') hier zodat inclusies in HTML de output niet verstoren.

$log_dir = '/var/private/logs/';
$recordings_dir = '/var/private/opnames/';
$ffmpeg_path = '/usr/bin/ffmpeg';

// Zorg dat de benodigde mappen bestaan
if (!is_dir($log_dir)) {
    mkdir($log_dir, 0777, true);
}
if (!is_dir($recordings_dir)) {
    mkdir($recordings_dir, 0777, true);
}

/**
 * Logt berichten naar /var/private/logs/recordings.log.
 */
function log_message($message) {
    global $log_dir;
    $logfile = $log_dir . "recordings.log";
    file_put_contents($logfile, '[' . date('Y-m-d H:i:s') . '] ' . $message . "\n", FILE_APPEND);
}

/**
 * Retourneert een PDO-verbinding met de SQLite-database.
 */
function getDbConnection() {
    define('DB_FILE', '/var/private/db/radiologger.db');
    try {
        $pdo = new PDO('sqlite:' . DB_FILE);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        return $pdo;
    } catch (PDOException $e) {
        log_message("DB connectie mislukt: " . $e->getMessage());
        echo json_encode(['error' => 'Database connectie mislukt']);
        exit;
    }
}

/**
 * Haalt alle stationrecords op uit de database en bouwt een compatibele datastructuur.
 */
function getStationsFromDb() {
    $pdo = getDbConnection();
    $stmt = $pdo->query("SELECT * FROM stations");
    $stations = $stmt->fetchAll(PDO::FETCH_ASSOC);
    foreach ($stations as &$station) {
        if (isset($station['schedule_start_date']) && $station['schedule_start_date'] !== null) {
            $station['schedule'] = [
                'start_date' => $station['schedule_start_date'],
                'start_hour' => $station['schedule_start_hour'],
                'end_date'   => $station['schedule_end_date'],
                'end_hour'   => $station['schedule_end_hour']
            ];
        } else {
            $station['schedule'] = null;
        }
        // Voeg voor compatibiliteit het veld 'url' toe met de waarde uit recording_url
        $station['url'] = $station['recording_url'];
    }
    return $stations;
}

/**
 * Helperfuncties voor stream-resolutie.
 */
function resolvePlaylistUrl($url) {
    if (preg_match('/\.(pls|m3u)$/i', $url)) {
        $streams = extractStreams($url);
        if (!empty($streams)) {
            return $streams[0];
        }
    }
    return $url;
}

function fixShoutcastV1Url($url) {
    if (substr($url, -1) === '/' && substr($url, -1) !== ';') {
        return $url . ';';
    }
    return $url;
}

function extractStreams($url) {
    $content = @file_get_contents($url);
    if ($content === false) {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (compatible; streamtest)');
        $content = curl_exec($ch);
        curl_close($ch);
        if ($content === false) {
            return [];
        }
    }
    $streams = [];
    if (preg_match('/\.pls$/i', $url)) {
        preg_match_all('/^\s*File\d+\s*=\s*(.+)$/mi', $content, $matches);
        if (!empty($matches[1])) {
            foreach ($matches[1] as $stream) {
                $stream = trim($stream);
                if (!empty($stream)) {
                    $streams[] = $stream;
                }
            }
        }
    } elseif (preg_match('/\.m3u$/i', $url)) {
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
 * Genereert het output-patroon voor ffmpeg-segmentatie.
 * Formaat: /var/private/opnames/StationNaam/YYYY-MM-DD/%H.mp3
 * De originele stationnaam wordt gebruikt.
 * 
 * Wijziging: Als het huidige uur 00:00 is, wordt de datum van vandaag gebruikt;
 * voor alle andere uren wordt de datum van één uur geleden gebruikt.
 */
function generateOutputPattern($stationName) {
    global $recordings_dir;
    $cleanName = trim($stationName);
    $currentHour = date('H');
    if ($currentHour === '00') {
        $date = date('Y-m-d');
    } else {
        $date = date('Y-m-d', strtotime('-1 hour'));
    }
    $directory = "$recordings_dir/$cleanName/$date";
    if (!is_dir($directory)) {
        mkdir($directory, 0777, true);
    }
    return $directory . "/%H.mp3";
}

/**
 * PREP: Controleert de beschikbare schijfruimte.
 */
function prep_for_recording() {
    global $recordings_dir;
    log_message("🔄 PREP-modus gestart");
    $disk_free = disk_free_space($recordings_dir) / (1024 * 1024 * 1024);
    if ($disk_free < 2) {
        log_message("⚠️ Weinig schijfruimte: " . round($disk_free, 2) . " GB over");
        echo json_encode(['status' => 'Fout: onvoldoende schijfruimte']);
        return;
    }
    log_message("✅ PREP voltooid");
    echo json_encode(['status' => 'PREP voltooid']);
}

/**
 * Start Always-On en geplande opnames met segmentatie.
 */
function start_scheduled_recordings() {
    global $ffmpeg_path, $recordings_dir;
    log_message("⏳ Start geplande en AO opnames");
    $stations = getStationsFromDb();
    $current_time = time();
    $process_output = shell_exec("pgrep -af ffmpeg");
    $process_lines = array_filter(explode("\n", trim($process_output)));

    foreach ($stations as $station) {
        $stationName = $station['name'];
        $rawUrl = $station['url'];
        $resolved = resolvePlaylistUrl($rawUrl);
        $stationUrl = fixShoutcastV1Url($resolved);

        $isAO = isset($station['always_on']) && $station['always_on'];
        $hasSchedule = !empty($station['schedule']);
        $inSchedule = false;
        if ($hasSchedule) {
            $schedule = $station['schedule'];
            $start_time = strtotime("{$schedule['start_date']} {$schedule['start_hour']}:00");
            $end_time = strtotime("{$schedule['end_date']} {$schedule['end_hour']}:00");
            if ($current_time >= $start_time && $current_time < $end_time) {
                $inSchedule = true;
            }
        }

        if ($isAO || ($hasSchedule && $inSchedule)) {
            $disk_free = disk_free_space($recordings_dir) / (1024 * 1024 * 1024);
            if ($disk_free < 2) {
                log_message("⚠️ Weinig schijfruimte: " . round($disk_free, 2) . " GB. Opname niet gestart voor {$stationName}.");
                continue;
            }
            $outputPattern = generateOutputPattern($stationName);
            $expectedDir = dirname($outputPattern);
            $processFound = false;
            $processesToKill = [];
            foreach ($process_lines as $line) {
                if (strpos($line, $rawUrl) !== false || strpos($line, $stationUrl) !== false) {
                    if (strpos($line, $expectedDir) !== false) {
                        $processFound = true;
                        break;
                    } else {
                        $parts = explode(" ", $line, 2);
                        if (!empty($parts[0])) {
                            $processesToKill[] = $parts[0];
                        }
                    }
                }
            }
            if (!empty($processesToKill)) {
                foreach ($processesToKill as $pid) {
                    exec("kill $pid");
                    log_message("🛑 Oude opname voor {$stationName} (PID $pid) gestopt.");
                }
            }
            if (!$processFound) {
                $stream_url = escapeshellarg($stationUrl);
                $output_arg = escapeshellarg($outputPattern);
                $command = "TZ='Europe/Amsterdam' $ffmpeg_path -i $stream_url -vn -acodec copy -f segment -segment_time 3600 -reset_timestamps 1 -segment_atclocktime 1 -strftime 1 $output_arg > /dev/null 2>&1 &";
                log_message("🎤 Opname starten voor {$stationName} (output: $outputPattern).");
                exec($command);
            }
        } else {
            foreach ($process_lines as $line) {
                if (strpos($line, $rawUrl) !== false || strpos($line, $stationUrl) !== false) {
                    $parts = explode(" ", $line, 2);
                    if (!empty($parts[0])) {
                        exec("kill {$parts[0]}");
                        log_message("🛑 Opname voor {$stationName} gestopt (niet in schema).");
                    }
                }
            }
        }
    }
}

/**
 * Start een handmatige opname (1 uur) voor een gegeven station.
 */
function start_manual_recording($station_name) {
    global $ffmpeg_path, $recordings_dir;
    $stations = getStationsFromDb();
    foreach ($stations as $station) {
        if ($station['name'] === $station_name) {
            $disk_free = disk_free_space($recordings_dir) / (1024 * 1024 * 1024);
            if ($disk_free < 2) {
                log_message("⚠️ Weinig schijfruimte: " . round($disk_free, 2) . " GB. Geen handmatige opname.");
                echo json_encode(['error' => 'Onvoldoende schijfruimte']);
                return;
            }
            $rawUrl = $station['url'];
            $resolved = resolvePlaylistUrl($rawUrl);
            $stream_fixed = fixShoutcastV1Url($resolved);
            $stream_arg = escapeshellarg($stream_fixed);
            $date = date('Y-m-d');
            $cleanStation = trim($station_name);
            $directory = "$recordings_dir/$cleanStation/$date";
            if (!is_dir($directory)) {
                mkdir($directory, 0777, true);
            }
            $hour_raw = date('H'); // Verwacht een getal met twee cijfers
            // Gebruik sprintf in plaats van printf
            $hour = sprintf("%02d:00", $hour_raw);
            $filePath = "$directory/$hour_raw.mp3";
            $command = "TZ='Europe/Amsterdam' $ffmpeg_path -i $stream_arg -vn -acodec copy -t 3600 " . escapeshellarg($filePath) . " > /dev/null 2>&1 &";
            exec($command);
            log_message("🎤 Handmatige opname gestart voor {$station_name}, file=$filePath");
            echo json_encode(['status' => 'Opname gestart', 'file' => $filePath]);
            return;
        }
    }
    echo json_encode(['error' => 'Station niet gevonden']);
}

/**
 * Stop alle lopende opnames.
 */
function stop_all_recordings() {
    exec("pkill -f ffmpeg");
    log_message("🛑 Alle opnames gestopt");
    echo json_encode(['status' => 'Alle opnames gestopt']);
}

/**
 * Toont de inhoud van het logbestand.
 */
function view_logs() {
    global $log_dir;
    $logfile = $log_dir . "recordings.log";
    if (file_exists($logfile)) {
        header('Content-Type: text/html; charset=utf-8');
        echo nl2br(file_get_contents($logfile));
    } else {
        echo json_encode(['error' => 'Geen logs beschikbaar']);
    }
}

/**
 * Dispatcher: Voer de API-acties uit als dit script direct wordt aangeroepen.
 * Als het script wordt geïncludeerd (bijvoorbeeld door admin.php), wordt dit gedeelte overgeslagen.
 */
if (realpath(__FILE__) === realpath($_SERVER['SCRIPT_FILENAME'])) {
    header('Content-Type: application/json');
    $action = $_GET['action'] ?? '';
    log_message("DEBUG: Actie ontvangen -> $action");

    switch ($action) {
        case 'prep':
            prep_for_recording();
            break;
        case 'start_scheduled':
            log_message("DEBUG: start_scheduled_recordings() wordt uitgevoerd.");
            start_scheduled_recordings();
            echo json_encode(['status' => 'Scheduled recordings gestart']);
            break;
        case 'start_manual':
            if (isset($_GET['station'])) {
                start_manual_recording($_GET['station']);
            } else {
                echo json_encode(['error' => 'Station-parameter ontbreekt']);
            }
            break;
        case 'stop_all':
            stop_all_recordings();
            break;
        case 'view_logs':
            view_logs();
            break;
        default:
            log_message("❌ Ongeldige actie: $action");
            echo json_encode(['error' => 'Ongeldige actie']);
            break;
    }
}
?>
