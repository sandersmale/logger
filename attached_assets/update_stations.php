<?php
// update_stations.php - Verwerkt de form submit van dennis.php en update de visible_in_logger status in de 'dennis' tabel

// Open de SQLite database
$dbPath = '/var/private/db/radiologger.db';
$db = new SQLite3($dbPath);

// Lees de geselecteerde station IDs uit het formulier
$selected = isset($_POST['stations']) ? $_POST['stations'] : [];
$selected = array_map('strval', $selected);

// Haal alle station IDs uit de 'dennis' tabel op
$results = $db->query("SELECT id FROM dennis");
$allIDs = [];
while ($row = $results->fetchArray(SQLITE3_ASSOC)) {
    $allIDs[] = strval($row['id']);
}

// Bereid een statement voor om het veld visible_in_logger bij te werken
$stmt = $db->prepare("UPDATE dennis SET visible_in_logger = :vis, last_updated = CURRENT_TIMESTAMP WHERE id = :id");
foreach ($allIDs as $id) {
    $vis = in_array($id, $selected) ? 1 : 0;
    $stmt->bindValue(':vis', $vis, SQLITE3_INTEGER);
    $stmt->bindValue(':id', $id, SQLITE3_INTEGER);
    $stmt->execute();
}

// Sluit de database en redirect terug naar dennis.php
header("Location: dennis.php");
exit;
?>
