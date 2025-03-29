<?php
session_start();

// Als de gebruiker niet ingelogd is, sla de huidige URL op en redirect naar login.php
if (!isset($_SESSION['user'])) {
    if (!isset($_SESSION['redirect_to'])) {
        $_SESSION['redirect_to'] = $_SERVER['REQUEST_URI'];
    }
    header("Location: login.php");
    exit;
}

// Extra restrictie voor gebruikers met de rol 'listener'
// Zij mogen enkel toegang hebben tot list_recordings.php, player.php, login.php en logout.php.
if ($_SESSION['role'] === 'listener') {
    // Definieer de toegestane pagina's voor listeners.
    $allowed_pages = ['list_recordings.php', 'player.php', 'login.php', 'logout.php'];
    // Haal de huidige bestandsnaam op (bijv. admin.php, add_station.php, enz.)
    $current_page = basename($_SERVER['PHP_SELF']);
    if (!in_array($current_page, $allowed_pages)) {
        header("Location: list_recordings.php");
        exit;
    }
}
?>
