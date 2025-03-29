<?php
require_once '/var/private/auth.php';
if (!isset($_GET['station'])) {
    echo "Geen station opgegeven.";
    exit();
}

$stations_file = '/var/private/stations.json';
$stations = json_decode(file_get_contents($stations_file), true);
$station_name = $_GET['station'];

foreach ($stations as $s) {
    if ($s['name'] === $station_name) {
        $stream_url = $s['url'];
        $filename = "opnames/" . preg_replace('/[^a-zA-Z0-9]/', '_', $station_name) . "_" . date('Ymd_His') . ".mp3";
        $command = "/usr/bin/ffmpeg -i "$stream_url" -vn -acodec libmp3lame -q:a 2 "$filename" > /dev/null 2>&1 &";
        exec($command);
        echo "Opname gestart voor $station_name.";
        exit();
    }
}

echo "Station niet gevonden.";
