<?php
// Stel de sessiecookie-lifetime in op 7 dagen (604800 seconden)
session_set_cookie_params(604800);
// Verhoog de maximale levensduur van de sessie (gc_maxlifetime)
ini_set('session.gc_maxlifetime', 604800);
session_start();
require_once '/var/private/api.php'; // Zorg dat getDbConnection() beschikbaar is

$error = "";
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = trim($_POST['password'] ?? '');
    
    if (empty($username) || empty($password)) {
        $error = "Vul zowel gebruikersnaam als wachtwoord in.";
    } else {
        $pdo = getDbConnection();
        $stmt = $pdo->prepare("SELECT * FROM users WHERE username = ?");
        $stmt->execute([$username]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        if ($user && password_verify($password, $user['password'])) {
            $_SESSION['user'] = $user['username'];
            $_SESSION['role'] = $user['role'];
            // Redirect naar de oorspronkelijk aangevraagde URL, indien aanwezig
            if (isset($_SESSION['redirect_to'])) {
                $redirect = $_SESSION['redirect_to'];
                unset($_SESSION['redirect_to']);
                header("Location: $redirect");
            } else {
                header("Location: admin.php");
            }
            exit;
        } else {
            $error = "Ongeldige gebruikersnaam of wachtwoord.";
        }
    }
}
?>
<!DOCTYPE html>
<html lang="nl">
<head>
    <meta charset="UTF-8">
    <title>Login Radiologger</title>
</head>
<body>
    <h1>Login Radiologger</h1>
    <?php if (!empty($error)): ?>
        <p style="color:red;"><?php echo $error; ?></p>
    <?php endif; ?>
    <form method="post" action="login.php">
        <label for="username">Gebruikersnaam:</label><br>
        <input type="text" id="username" name="username" required><br><br>
        <label for="password">Wachtwoord:</label><br>
        <input type="password" id="password" name="password" required><br><br>
        <button type="submit">Inloggen</button>
    </form>
</body>
</html>
