<?php
// dennis.php - Beheerpagina voor Dennis' stations

// Open de SQLite database
$dbPath = '/var/private/db/radiologger.db';
$db = new SQLite3($dbPath);

// Haal alle records uit de 'dennis' tabel
$results = $db->query("SELECT id, folder, name, url, visible_in_logger FROM dennis ORDER BY name ASC");
$stations = [];
while ($row = $results->fetchArray(SQLITE3_ASSOC)) {
    $stations[] = $row;
}
?>
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Dennis' Stations Beheer</title>
    <style>
      body { font-family: Arial, sans-serif; }
      h1, h3 { color: #333; }
      label { display: block; margin: 5px 0; }
      button { margin: 10px 0; }
    </style>
</head>
<body>
    <h1>Dennis' Stations Beheer</h1>
    
    <!-- Vernieuw-knop: dit roept update_dennis_api.php aan -->
    <form method="post" action="update_dennis_api.php" style="display:inline;">
        <button type="submit">Vernieuw lijst via API</button>
    </form>
    
    <hr>
    
    <form method="post" action="update_stations.php">
        <h3>Stations in de logger (aan)</h3>
        <?php 
        $hasIn = false;
        foreach ($stations as $station) {
            if ($station['visible_in_logger'] == 1) {
                $hasIn = true;
                echo '<label>';
                echo '<input type="checkbox" name="stations[]" value="' . htmlspecialchars($station['id']) . '" checked> ';
                echo htmlspecialchars($station['name']) . " (" . htmlspecialchars($station['folder']) . ")";
                echo '</label>';
            }
        }
        if (!$hasIn) {
            echo "<p><em>Geen stations in de logger.</em></p>";
        }
        ?>
        
        <h3>Stations niet in de logger (uit)</h3>
        <?php 
        $hasOut = false;
        foreach ($stations as $station) {
            if ($station['visible_in_logger'] == 0) {
                $hasOut = true;
                echo '<label>';
                echo '<input type="checkbox" name="stations[]" value="' . htmlspecialchars($station['id']) . '"> ';
                echo htmlspecialchars($station['name']) . " (" . htmlspecialchars($station['folder']) . ")";
                echo '</label>';
            }
        }
        if (!$hasOut) {
            echo "<p><em>Alle stations staan al in de logger.</em></p>";
        }
        ?>
        
        <br>
        <button type="submit">Opslaan</button>
    </form>
</body>
</html>
