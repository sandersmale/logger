<?php
/**
 * cpu_info.php
 * Eenvoudig statusoverzicht voor CPU, RAM en disk.
 * Schrijft in 'gewone mensentaal' wat de server doet.
 */

// We geven HTML-output:
header('Content-Type: text/html; charset=utf-8');

// Kleine helper om netjes af te ronden:
function roundDec($value, $dec=1) {
    return round($value, $dec);
}

//------------------------------------------------------------------------------
// 1) CPU-gebruik via top (2 cycli, korte delay)
//------------------------------------------------------------------------------
$topOutput = shell_exec("top -bn2 -d 0.3 | grep 'Cpu(s)' | tail -n 1");
// top-regel heeft vaak de vorm:
// "Cpu(s):  5.3%us,  1.1%sy,  0.0%ni, 92.9%id,  0.1%wa, 0.0%hi, 0.6%si, 0.0%st"
$cpuUser = $cpuSys = $cpuIdle = '?';
if (preg_match('/(\d+\.\d+)\s*us,?\s+(\d+\.\d+)\s*sy,.*?(\d+\.\d+)\s*id/', $topOutput, $m)) {
    $cpuUser = (float)$m[1];
    $cpuSys  = (float)$m[2];
    $cpuIdle = (float)$m[3];
}
$cpuUsed = $cpuUser + $cpuSys; // globale indicatie

//------------------------------------------------------------------------------
// 2) Load average uit /proc/loadavg
//------------------------------------------------------------------------------
$load_1  = $load_5 = $load_15 = '?';
$loadavgRaw = @file_get_contents('/proc/loadavg');
if ($loadavgRaw !== false) {
    $parts = explode(' ', $loadavgRaw);
    if (count($parts) >= 3) {
        $load_1  = $parts[0];
        $load_5  = $parts[1];
        $load_15 = $parts[2];
    }
}

//------------------------------------------------------------------------------
// 3) RAM-gebruik via free -m
//------------------------------------------------------------------------------
$totalMem = $usedMem = $freeMem = 0;
$memOutput = shell_exec("free -m");
if ($memOutput) {
    $lines = explode("\n", trim($memOutput));
    if (count($lines) >= 2) {
        // typ. "Mem:  3953  3148  804 ..."
        $memLine = preg_split('/\s+/', $lines[1]); // 2e regel
        if (count($memLine) >= 4) {
            // [0] => Mem:, [1] => total, [2] => used, [3] => free ...
            $totalMem = (int)$memLine[1];
            $usedMem  = (int)$memLine[2];
            $freeMem  = (int)$memLine[3];
        }
    }
}

//------------------------------------------------------------------------------
// 4) Disk-gebruik: df -h (alleen rootpartitie en evt. extra info)
//------------------------------------------------------------------------------
$diskOutput = shell_exec("df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs | grep -v 'Filesystem'");
// Bv:
// " /dev/vda1   50G   10G   37G  22%  /"
//
// We laten in de output alles zien, maar houden het simpel.

?>
<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8">
  <title>Serverstatus in eenvoudige taal</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1, h2 { margin-bottom: 0.3em; }
    pre { background: #f0f0f0; padding: 10px; }
    .highlight { font-weight: bold; color: #c00; }
  </style>
</head>
<body>

<h1>Serverstatus</h1>

<!-- CPU-gebruik -->
<section>
  <h2>CPU-gebruik</h2>
  <p>
    De server is momenteel ongeveer 
    <span class="highlight"><?= roundDec($cpuUsed, 1) ?>%</span> van zijn CPU aan het gebruiken.
  </p>
  <ul>
    <li>Gebruikersprocessen: <?= roundDec($cpuUser, 1) ?>%</li>
    <li>Systeemprocessen: <?= roundDec($cpuSys, 1) ?>%</li>
    <li>Rust (idle): <?= roundDec($cpuIdle, 1) ?>%</li>
  </ul>
  <p>
    <small>Als dit (totaal) boven de ~70-80% komt, kan de server het zwaar krijgen.</small>
  </p>
</section>

<!-- Load average -->
<section>
  <h2>Load Gemiddelden</h2>
  <p>
    Dit is een andere manier om te zien hoe druk de server is:
  </p>
  <ul>
    <li>Laatste 1 minuut: <strong><?= $load_1 ?></strong></li>
    <li>Laatste 5 minuten: <strong><?= $load_5 ?></strong></li>
    <li>Laatste 15 minuten: <strong><?= $load_15 ?></strong></li>
  </ul>
  <p><small>Grofweg geldt: een load die lager is dan het aantal CPU-cores is prima.</small></p>
</section>

<!-- RAM-gebruik -->
<section>
  <h2>RAM-gebruik</h2>
  <p>
    De server heeft totaal 
    <strong><?= $totalMem ?> MB</strong> geheugen. 
    Daarvan is 
    <span class="highlight"><?= $usedMem ?> MB</span> in gebruik 
    en er is nog 
    <strong><?= $freeMem ?> MB</strong> vrij.
  </p>
  <p><small>Als 'vrij' < 10% van totaal is, kan de server onder geheugenstress komen.</small></p>
</section>

<!-- Diskgebruik -->
<section>
  <h2>Schijfruimte</h2>
  <p>
    Hieronder zie je hoeveel schijfruimte gebruikt is. 
    Let vooral op je root-partitie (vaak <code>/dev/vda1</code> of <code>/dev/sda1</code>).
  </p>
  <pre><?= trim($diskOutput) ?></pre>
  <p>
    <small>Stijgt je schijfruimte richting 90% of 100%, dan moet je ruimte vrijmaken of vergroten.</small>
  </p>
</section>

<hr>
<p><em>Laatste update: <?= date('Y-m-d H:i:s') ?>. Ververs deze pagina voor actuele status.</em></p>

</body>
</html>
