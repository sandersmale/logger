<?php
require_once '/var/private/api.php'; // Zorg dat hierin getDbConnection() is gedefinieerd
require_once '/var/private/auth.php';
if (!isset($_GET['name'])) {
    echo "Geen station opgegeven.";
    exit();
}

$name = $_GET['name'];
$pdo = getDbConnection();

$stmt = $pdo->prepare("DELETE FROM stations WHERE name = ?");
$stmt->execute([$name]);

header('Location: admin.php');
exit();
