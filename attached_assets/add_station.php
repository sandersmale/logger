<?php
require_once '/var/private/auth.php';
require_once '/var/private/api.php'; // Zorg dat hierin getDbConnection() en getStationsFromDb() gedefinieerd staan.

ini_set('display_errors', 1);
error_reporting(E_ALL);
date_default_timezone_set('Europe/Amsterdam');

/**
 * Test de ingevoerde URL door test_stream.php aan te roepen via cURL.
 * Verwacht een JSON-response met 'stream_url' of een 'error'.
 */
function getBestStream($url, &$error_message) {
    // Bouw de URL voor de test_stream.php call
    $test_url = "http://localhost:8080/test_stream.php?url=" . urlencode($url);
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $test_url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    $response = curl_exec($ch);
    if (curl_errno($ch)) {
        $error_message = "cURL fout: " . curl_error($ch);
        curl_close($ch);
        return false;
    }
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($httpCode !== 200) {
        $error_message = "HTTP fout: code $httpCode bij streamtest.";
        return false;
    }
    $data = json_decode($response, true);
    if (!$data) {
        $error_message = "Ongeldige JSON respons.";
        return false;
    }
    if (isset($data['error'])) {
        $error_message = $data['error'];
        return false;
    }
    if (!isset($data['stream_url'])) {
        $error_message = "Geen 'stream_url' in test_stream respons.";
        return false;
    }
    $bestStream = trim($data['stream_url']);
    return $bestStream;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $name = trim($_POST['name'] ?? '');
    $url = trim($_POST['url'] ?? '');
    $scheduleEnabled = isset($_POST['schedule_enabled']);
    
    if (!empty($name) && !empty($url)) {
        $error_message = "";
        $bestStream = getBestStream($url, $error_message);
        
        if (!$bestStream) {
            echo "<p style='color:red;'>Fout: $error_message</p>";
        } else {
            $pdo = getDbConnection();
            // Controleer of er al een station met dezelfde naam bestaat
            $stmt = $pdo->prepare("SELECT COUNT(*) FROM stations WHERE name = ?");
            $stmt->execute([$name]);
            if ($stmt->fetchColumn() > 0) {
                echo "<p style='color:red;'>Er bestaat al een station met de naam \"$name\". Kies een andere naam.</p>";
            } else {
                if ($scheduleEnabled) {
                    $always_on = 0;
                    $start_date = $_POST['start_date'] ?? null;
                    $start_hour = $_POST['start_hour'] ?? null;
                    $end_date   = $_POST['end_date'] ?? null;
                    $end_hour   = $_POST['end_hour'] ?? null;
                } else {
                    $always_on = 1;
                    $start_date = $start_hour = $end_date = $end_hour = null;
                }
                // Sla de originele URL op in user_defined_url en de geteste URL in recording_url.
                $recording_url = $bestStream;
                
                try {
                    $pdo->beginTransaction();
                    $stmt = $pdo->prepare("INSERT INTO stations 
                        (name, user_defined_url, recording_url, always_on, schedule_start_date, schedule_start_hour, schedule_end_date, schedule_end_hour)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
                    $stmt->execute([$name, $url, $recording_url, $always_on, $start_date, $start_hour, $end_date, $end_hour]);
                    $pdo->commit();
                    echo "<p style='color:green;'>Station \"$name\" toegevoegd! URL=$recording_url</p>";
                } catch (Exception $e) {
                    $pdo->rollBack();
                    echo "<p style='color:red;'>Fout bij toevoegen station: " . $e->getMessage() . "</p>";
                }
            }
        }
    } else {
        echo "<p style='color:red;'>Naam en stream-URL zijn verplicht.</p>";
    }
}
?>
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Radiostation toevoegen</title>
</head>
<body>
<h1>Radiostation toevoegen</h1>
<form method="POST" action="add_station.php">
    <div>
        <label for="name">Naam:</label>
        <input type="text" id="name" name="name" required>
    </div>
    <br>
    <div>
        <label for="url">Stream-URL:</label>
        <input type="text" id="url" name="url" required>
    </div>
    <br>
    <div>
        <input type="checkbox" id="schedule_enabled" name="schedule_enabled" onchange="toggleSchedule()">
        <label for="schedule_enabled">Opname plannen?</label>
    </div>
    <div id="schedule_section" style="display:none; margin-top:10px;">
        <label for="start_date">Startdatum:</label>
        <select id="start_date" name="start_date">
            <?php for ($i=0; $i<30; $i++):
                $d = date('Y-m-d', strtotime("+$i days")); ?>
                <option value="<?= htmlspecialchars($d) ?>"><?= date('d-m-Y', strtotime($d)) ?></option>
            <?php endfor; ?>
        </select>
        <br><br>
        <label for="start_hour">Startuur:</label>
        <select id="start_hour" name="start_hour">
            <?php for ($h=0; $h<24; $h++): ?>
                <option value="<?= htmlspecialchars($h) ?>"><?= sprintf('%02d:00', $h) ?></option>
            <?php endfor; ?>
        </select>
        <br><br>
        <label for="end_date">Einddatum:</label>
        <select id="end_date" name="end_date">
            <?php for ($i=0; $i<30; $i++):
                $d = date('Y-m-d', strtotime("+$i days")); ?>
                <option value="<?= htmlspecialchars($d) ?>"><?= date('d-m-Y', strtotime($d)) ?></option>
            <?php endfor; ?>
        </select>
        <br><br>
        <label for="end_hour">Einduur:</label>
        <select id="end_hour" name="end_hour">
            <?php for ($h=0; $h<24; $h++): ?>
                <option value="<?= htmlspecialchars($h) ?>"><?= sprintf('%02d:00', $h) ?></option>
            <?php endfor; ?>
        </select>
    </div>
    <br>
    <button type="submit">Toevoegen</button>
</form>

<script>
function toggleSchedule() {
    var checkBox = document.getElementById("schedule_enabled");
    var sec = document.getElementById("schedule_section");
    sec.style.display = checkBox.checked ? "block" : "none";
}
</script>
</body>
</html>
