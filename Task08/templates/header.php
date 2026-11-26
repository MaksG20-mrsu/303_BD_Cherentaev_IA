<?php
/**
 * Общая шапка страниц. Перед подключением нужно задать переменную $pageTitle.
 *
 * @var string $pageTitle
 */
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?= e($pageTitle) ?> - СТО</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
<header class="site-header">
    <a class="site-title" href="index.php">СТО</a>
    <nav>
        <a href="master_form.php">Мастера</a>
        <a href="schedule_form.php">График работы</a>
        <a href="appointment_form.php">Запись на обслуживание</a>
    </nav>
</header>
<main>
    <h1><?= e($pageTitle) ?></h1>
