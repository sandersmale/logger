<?php
// update_dennis_api.php - Roept het shell script /update_dennis.sh aan om de Dennis API te verversen

$scriptPath = '/update_dennis.sh';
$output = [];
$return_var = 0;
exec(escapeshellcmd($scriptPath) . " 2>&1", $output, $return_var);
if ($return_var !== 0) {
    echo "Fout bij het uitvoeren van update_dennis.sh:<br>";
    echo "<pre>" . htmlspecialchars(implode("\n", $output)) . "</pre>";
} else {
    echo "De lijst is succesvol ververst.<br>";
}
echo '<p><a href="dennis.php">Terug naar Dennis\' stations</a></p>';
?>
