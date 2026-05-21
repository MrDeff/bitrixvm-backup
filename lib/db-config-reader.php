<?php
declare(strict_types=1);

if ($argc !== 2) {
    fwrite(STDERR, "Usage: db-config-reader.php <site-root>\n");
    exit(2);
}

$siteRoot = rtrim($argv[1], '/');
$settingsPath = $siteRoot . '/bitrix/.settings.php';
$dbconnPath = $siteRoot . '/bitrix/php_interface/dbconn.php';

function emit_config(array $config): void
{
    foreach (['host', 'database', 'login', 'password'] as $field) {
        if (!array_key_exists($field, $config) || !is_scalar($config[$field])) {
            fwrite(STDERR, "Invalid Bitrix database config: {$field} must be a scalar value\n");
            exit(1);
        }
    }

    echo json_encode([
        'host' => (string)$config['host'],
        'database' => (string)$config['database'],
        'login' => (string)$config['login'],
        'password' => (string)$config['password'],
        'source' => (string)$config['source'],
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . PHP_EOL;
}

if (is_readable($settingsPath)) {
    $settings = include $settingsPath;
    $default = [];

    if (is_array($settings)) {
        $default = $settings['connections']['value']['default'] ?? [];
    }

    emit_config([
        'host' => $default['host'] ?? '',
        'database' => $default['database'] ?? '',
        'login' => $default['login'] ?? '',
        'password' => $default['password'] ?? '',
        'source' => $settingsPath,
    ]);
    exit(0);
}

if (is_readable($dbconnPath)) {
    $DBHost = 'localhost';
    $DBName = '';
    $DBLogin = '';
    $DBPassword = '';

    include $dbconnPath;

    emit_config([
        'host' => $DBHost,
        'database' => $DBName,
        'login' => $DBLogin,
        'password' => $DBPassword,
        'source' => $dbconnPath,
    ]);
    exit(0);
}

fwrite(STDERR, "No readable Bitrix database config found under {$siteRoot}\n");
exit(1);
