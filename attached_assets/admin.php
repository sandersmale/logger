<?php
// Eerst de API-functies insluiten zodat getStationsFromDb() beschikbaar is
require_once '/var/private/api.php';
// Daarna de authenticatie, zodat de sessie gecontroleerd wordt
require_once '/var/private/auth.php';

date_default_timezone_set('Europe/Amsterdam');

$stations = getStationsFromDb();
?>
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Radiologger Beheer</title>
</head>
<body>
    <h1>Radiologger Beheer</h1>
    <p>Je bent ingelogd als: <strong><?php echo htmlspecialchars($_SESSION['user']); ?></strong> (Rol: <?php echo htmlspecialchars($_SESSION['role']); ?>)</p>
    <p><a href="logout.php">Uitloggen</a></p>

    <h2>📻 Opnames</h2>
    <p><a href="list_recordings.php">Bekijk beschikbare opnames</a></p>

    <?php
    // Filter Always-On (AO) stations
    $ao_stations = array_filter($stations, function($s) {
        return isset($s['always_on']) && $s['always_on'] == 1;
    });
    // Filter geplande stations: stations met een schema waarvan de eindtijd nog in de toekomst ligt
    $sched_stations = array_filter($stations, function($s) {
        if (empty($s['schedule'])) {
            return false;
        }
        $end_time = strtotime($s['schedule']['end_date'] . ' ' . $s['schedule']['end_hour'] . ':00');
        return (time() < $end_time);
    });
    ?>

    <h2>🎤 AO-Stations (24/7)</h2>
    <?php if (!empty($ao_stations)): ?>
        <?php foreach ($ao_stations as $station): ?>
            <p><?php echo htmlspecialchars($station['name']); ?>
            <?php if ($_SESSION['role'] !== 'listener'): ?>
                <a href="delete_station.php?name=<?php echo urlencode($station['name']); ?>">[Verwijderen]</a>
            <?php endif; ?>
            </p>
        <?php endforeach; ?>
    <?php else: ?>
        <p>(Geen AO-stations aanwezig)</p>
    <?php endif; ?>

    <h2>📅 Geplande Stations</h2>
    <?php if (!empty($sched_stations)): ?>
        <?php foreach ($sched_stations as $station):
            $name  = htmlspecialchars($station['name']);
            $sch   = $station['schedule'];
            $startH = $sch['start_hour'] ?? '?';
            $endH   = $sch['end_hour'] ?? '?';
        ?>
            <p><?php echo $name; ?> (<?php echo $startH; ?>:00 - <?php echo $endH; ?>:00)
            <?php if ($_SESSION['role'] !== 'listener'): ?>
                <a href="delete_station.php?name=<?php echo urlencode($station['name']); ?>">[Verwijderen]</a>
            <?php endif; ?>
            </p>
        <?php endforeach; ?>
    <?php else: ?>
        <p>(Geen geplande stations)</p>
    <?php endif; ?>

    <p><a href="add_station.php">📌 Voeg een nieuw station toe</a></p>

    <?php if ($_SESSION['role'] === 'admin'): ?>
        <h2>Beheertaken</h2>
        <!-- Links naar API-acties via het nieuwe pad -->
        <p><a href="/var/private/api.php?action=prep" target="_blank">Prep</a> – controleert schijfruimte</p>
        <p><a href="/var/private/api.php?action=start_scheduled" target="_blank">Start Scheduled</a> – start AO+geplande opnames</p>
        <p><a href="/var/private/api.php?action=stop_all" target="_blank">Stop alle opnames</a></p>
        <p><a href="/var/private/api.php?action=view_logs" target="_blank">Bekijk logs</a></p>
        <?php if (!empty($stations)): ?>
            <h3>Handmatige opname starten</h3>
            <form action="/var/private/api.php" method="get" target="_blank">
                <input type="hidden" name="action" value="start_manual" />
                Kies station: 
                <select name="station">
                    <?php foreach ($stations as $s): ?>
                        <option value="<?php echo htmlspecialchars($s['name']); ?>"><?php echo htmlspecialchars($s['name']); ?></option>
                    <?php endforeach; ?>
                </select>
                <button type="submit">Start Manual Recording (1 uur)</button>
            </form>
        <?php endif; ?>
    <?php elseif ($_SESSION['role'] === 'editor'): ?>
        <h2>Beheertaken</h2>
        <p><a href="/var/private/api.php?action=prep" target="_blank">Prep</a> – controleert schijfruimte</p>
        <p><a href="/var/private/api.php?action=view_logs" target="_blank">Bekijk logs</a></p>
    <?php endif; ?>

</body>
</html>
