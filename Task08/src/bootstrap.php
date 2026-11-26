<?php

declare(strict_types=1);

/**
 * Общая инициализация для всех страниц сайта (подключается из каталога public).
 */

date_default_timezone_set('Europe/Moscow');

// Файл базы данных лежит в каталоге Task08/data (на уровень выше каталога src).
define('DATABASE_PATH', dirname(__DIR__) . '/data/sto.db');
define('INIT_SCRIPT_PATH', dirname(__DIR__) . '/data/db_init.sql');

/** Шаг сетки времени для записи, в минутах. */
const SLOT_STEP_MINUTES = 15;

require __DIR__ . '/helpers.php';
require __DIR__ . '/database.php';
require __DIR__ . '/validation.php';
