<?php
require_once '/var/private/auth.php';
define('STATIONS_FILE', '/var/www/html/stations.json');

if (!file_exists(STATIONS_FILE)) {
    if (file_put_contents(STATIONS_FILE, json_encode([])) === false) {
        die("Fout: Kan stations.json niet aanmaken. Controleer bestandsrechten.");
    }
}

$jsonContent = file_get_contents(STATIONS_FILE);
$data = json_decode($jsonContent, true);
if (json_last_error() !== JSON_ERROR_NONE || !is_array($data)) {
    die("Fout: Kan stations.json niet lezen of JSON is beschadigd.");
}

$name = htmlspecialchars(trim($_POST['station_name'] ?? ''));
$url = filter_var(trim($_POST['stream_url'] ?? ''), FILTER_VALIDATE_URL);
$schedule = isset($_POST['schedule']);
$start_date = $_POST['start_date'] ?? null;
$start_hour = $_POST['start_hour'] ?? null;
$end_date = $_POST['end_date'] ?? null;
$end_hour = $_POST['end_hour'] ?? null;
$reason = htmlspecialchars($_POST['record_reason'] ?? 'Geen reden opgegeven');

if (empty($name) || !$url) {
    die("Fout: Naam en een geldige URL zijn verplicht.");
}

foreach ($data as $station) {
    if ($station['name'] === $name) {
        die("Fout: Dit station bestaat al.");
    }
}

$new_station = [
    "name" => $name,
    "url" => $url
];

if ($schedule) {
    $new_station["schedule"] = [
        "start_date" => $start_date,
        "start_hour" => (int)$start_hour,
        "end_date" => $end_date,
        "end_hour" => (int)$end_hour,
        "reason" => $reason
    ];
}

$data[] = $new_station;

if (file_put_contents(STATIONS_FILE, json_encode($data, JSON_PRETTY_PRINT)) === false) {
    die("Fout: Kan gegevens niet opslaan in stations.json. Controleer bestandsrechten.");
}

echo "Station succesvol toegevoegd.";
?>