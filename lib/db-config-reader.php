<?php
declare(strict_types=1);

if ($argc !== 2) {
    fwrite(STDERR, "Usage: db-config-reader.php <site-root>\n");
    exit(2);
}

$siteRoot = rtrim($argv[1], '/');
$settingsPath = $siteRoot . '/bitrix/.settings.php';
$dbconnPath = $siteRoot . '/bitrix/php_interface/dbconn.php';

if (is_readable($settingsPath)) {
    $settings = include $settingsPath;
    $default = [];

    if (is_array($settings)) {
        $default = $settings['connections']['value']['default'] ?? [];
    }

    echo json_encode([
        'host' => (string)($default['host'] ?? ''),
        'database' => (string)($default['database'] ?? ''),
        'login' => (string)($default['login'] ?? ''),
        'password' => (string)($default['password'] ?? ''),
        'source' => $settingsPath,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
    exit(0);
}

if (is_readable($dbconnPath)) {
    $DBHost = 'localhost';
    $DBName = '';
    $DBLogin = '';
    $DBPassword = '';

    include $dbconnPath;

    echo json_encode([
        'host' => (string)$DBHost,
        'database' => (string)$DBName,
        'login' => (string)$DBLogin,
        'password' => (string)$DBPassword,
        'source' => $dbconnPath,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
    exit(0);
}

fwrite(STDERR, "No readable Bitrix database config found under {$siteRoot}\n");
exit(1);
