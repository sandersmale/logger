<?php
require_once '/var/private/auth.php';
if ($_SESSION['role'] !== 'admin') {
    die("Geen toegang. Deze pagina is alleen beschikbaar voor admin-gebruikers.");
}

require_once '/var/private/api.php'; // Zorg dat getDbConnection() beschikbaar is
$pdo = getDbConnection();

$message = "";
$deleteMessage = "";

// Verwerken van een nieuwe gebruiker toevoegen (POST)
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action']) && $_POST['action'] === 'add_user') {
    $username = trim($_POST['username'] ?? '');
    $password = trim($_POST['password'] ?? '');
    $role = trim($_POST['role'] ?? 'listener');  // standaard: listener
    
    if (empty($username) || empty($password)) {
        $message = "Gebruikersnaam en wachtwoord zijn verplicht.";
    } else {
        // Controleer of de gebruiker al bestaat
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM users WHERE username = ?");
        $stmt->execute([$username]);
        if ($stmt->fetchColumn() > 0) {
            $message = "Gebruiker bestaat al.";
        } else {
            $hash = password_hash($password, PASSWORD_DEFAULT);
            $stmt = $pdo->prepare("INSERT INTO users (username, password, role) VALUES (?, ?, ?)");
            if ($stmt->execute([$username, $hash, $role])) {
                $message = "Gebruiker '$username' succesvol toegevoegd.";
            } else {
                $message = "Fout bij het toevoegen van de gebruiker.";
            }
        }
    }
}

// Verwerken van een verwijderactie (GET)
if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['delete'])) {
    $deleteUser = trim($_GET['delete']);
    // Voorkom dat je jezelf verwijdert
    if ($deleteUser === $_SESSION['user']) {
        $deleteMessage = "Je kunt je eigen account niet verwijderen.";
    } else {
        $stmt = $pdo->prepare("DELETE FROM users WHERE username = ?");
        if ($stmt->execute([$deleteUser])) {
            $deleteMessage = "Gebruiker '$deleteUser' is verwijderd.";
        } else {
            $deleteMessage = "Fout bij het verwijderen van gebruiker '$deleteUser'.";
        }
    }
}

// Haal alle gebruikers op
$stmt = $pdo->query("SELECT id, username, role FROM users ORDER BY username ASC");
$users = $stmt->fetchAll(PDO::FETCH_ASSOC);
?>
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Gebruikersbeheer</title>
    <style>
        table { border-collapse: collapse; }
        th, td { padding: 8px 12px; border: 1px solid #ccc; }
    </style>
</head>
<body>
    <h1>Gebruikersbeheer</h1>
    <p><a href="admin.php">Terug naar Beheer</a> | <a href="logout.php">Uitloggen</a></p>
    
    <?php if ($message): ?>
        <p style="color:green;"><?php echo htmlspecialchars($message); ?></p>
    <?php endif; ?>
    
    <?php if ($deleteMessage): ?>
        <p style="color:red;"><?php echo htmlspecialchars($deleteMessage); ?></p>
    <?php endif; ?>

    <h2>Voeg een nieuwe gebruiker toe</h2>
    <form method="post" action="user_management.php">
        <input type="hidden" name="action" value="add_user">
        <label for="username">Gebruikersnaam:</label><br>
        <input type="text" id="username" name="username" required><br><br>
        <label for="password">Wachtwoord:</label><br>
        <input type="password" id="password" name="password" required><br><br>
        <label for="role">Rol:</label><br>
        <select id="role" name="role">
            <option value="listener">Listener</option>
            <option value="editor">Editor</option>
            <option value="admin">Admin</option>
        </select><br><br>
        <button type="submit">Gebruiker toevoegen</button>
    </form>

    <h2>Bestaande gebruikers</h2>
    <table>
        <tr>
            <th>Gebruikersnaam</th>
            <th>Rol</th>
            <th>Acties</th>
        </tr>
        <?php foreach ($users as $user): ?>
            <tr>
                <td><?php echo htmlspecialchars($user['username']); ?></td>
                <td><?php echo htmlspecialchars($user['role']); ?></td>
                <td>
                    <?php if ($user['username'] !== $_SESSION['user']): ?>
                        <a href="user_management.php?delete=<?php echo urlencode($user['username']); ?>"
                           onclick="return confirm('Weet je zeker dat je deze gebruiker wilt verwijderen?');">
                           Verwijderen
                        </a>
                    <?php else: ?>
                        -
                    <?php endif; ?>
                </td>
            </tr>
        <?php endforeach; ?>
    </table>
</body>
</html>
