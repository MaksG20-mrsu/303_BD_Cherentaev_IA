<?php

declare(strict_types=1);

/**
 * Лабораторная работа 7, часть 1.
 * Консольный сценарий: список услуг, оказанных мастерами СТО, в виде таблицы
 * из символов псевдографики с фильтрацией по номеру мастера.
 *
 * Запуск: php task7_cli.php
 */

require __DIR__ . '/database.php';

/** Число символов в UTF-8 строке (не требует расширения mbstring). */
function text_length(string $text): int
{
    return (int) preg_match_all('/./su', $text);
}

/** Дополняет строку пробелами до нужной ширины (в символах, а не в байтах). */
function pad_text(string $text, int $width, bool $alignRight = false): string
{
    $padding = str_repeat(' ', max(0, $width - text_length($text)));

    return $alignRight ? $padding . $text : $text . $padding;
}

/**
 * Формирует таблицу из символов псевдографики.
 *
 * @param string[]   $headers             заголовки столбцов
 * @param string[][] $rows                строки таблицы (все ячейки - строки)
 * @param int[]      $rightAlignedColumns номера столбцов, выравниваемых по правому краю
 */
function render_table(array $headers, array $rows, array $rightAlignedColumns = []): string
{
    $widths = [];
    foreach ($headers as $index => $header) {
        $widths[$index] = text_length($header);
    }
    foreach ($rows as $row) {
        foreach ($row as $index => $cell) {
            $widths[$index] = max($widths[$index], text_length($cell));
        }
    }

    $makeBorder = function (string $left, string $middle, string $right) use ($widths): string {
        $segments = array_map(
            fn(int $width): string => str_repeat('─', $width + 2),
            $widths
        );

        return $left . implode($middle, $segments) . $right . PHP_EOL;
    };

    $makeRow = function (array $cells) use ($widths, $rightAlignedColumns): string {
        $parts = [];
        foreach ($cells as $index => $cell) {
            $isRightAligned = in_array($index, $rightAlignedColumns, true);
            $parts[] = ' ' . pad_text($cell, $widths[$index], $isRightAligned) . ' ';
        }

        return '│' . implode('│', $parts) . '│' . PHP_EOL;
    };

    $table = $makeBorder('┌', '┬', '┐');
    $table .= $makeRow($headers);
    $table .= $makeBorder('├', '┼', '┤');
    foreach ($rows as $row) {
        $table .= $makeRow($row);
    }
    $table .= $makeBorder('└', '┴', '┘');

    return $table;
}

/**
 * Запрашивает у пользователя номер мастера.
 * Enter (пустой ввод) означает «все мастера» и даёт null.
 * Вводимое значение проверяется: это должно быть целое число из списка номеров в базе.
 *
 * @param array<int, array{id: int|string}> $masters мастера, прочитанные из базы
 */
function read_master_id(array $masters): ?int
{
    $availableIds = array_map(
        fn(array $master): int => (int) $master['id'],
        $masters
    );

    while (true) {
        echo 'Введите номер мастера (Enter - показать всех мастеров): ';
        $line = fgets(STDIN);

        if ($line === false) { // конец ввода (Ctrl+Z / Ctrl+D или закрытый канал)
            echo PHP_EOL;

            return null;
        }

        $input = trim($line);
        if ($input === '') {
            return null;
        }

        if (preg_match('/^\d+$/', $input) === 1 && in_array((int) $input, $availableIds, true)) {
            return (int) $input;
        }

        echo 'Ошибка: нужно ввести один из номеров из списка выше или нажать Enter.' . PHP_EOL;
    }
}

try {
    $pdo = open_database();
    $masters = find_all_masters($pdo);

    if (count($masters) === 0) {
        echo 'В базе данных нет мастеров.' . PHP_EOL;
        exit(0);
    }

    echo 'Мастера станции технического обслуживания:' . PHP_EOL;
    foreach ($masters as $master) {
        $dismissedNote = ((int) $master['is_dismissed'] === 1) ? ' (уволен)' : '';
        echo sprintf('  %d - %s%s', (int) $master['id'], $master['full_name'], $dismissedNote) . PHP_EOL;
    }
    echo PHP_EOL;

    $selectedMasterId = read_master_id($masters);
    $works = find_performed_works($pdo, $selectedMasterId);
} catch (RuntimeException $exception) { // PDOException тоже наследует RuntimeException
    fwrite(STDERR, 'Ошибка при работе с базой данных: ' . $exception->getMessage() . PHP_EOL);
    exit(1);
}

echo PHP_EOL;

if (count($works) === 0) {
    echo 'Выполненных работ не найдено.' . PHP_EOL;
    exit(0);
}

$rows = [];
$totalPrice = 0.0;
foreach ($works as $work) {
    $price = (float) $work['price'];
    $totalPrice += $price;
    $rows[] = [
        (string) $work['master_id'],
        $work['master_full_name'],
        $work['work_date'],
        $work['service_name'],
        number_format($price, 2, '.', ' '),
    ];
}

$headers = ['Номер мастера', 'ФИО', 'Дата работы', 'Услуга', 'Стоимость'];
echo render_table($headers, $rows, [4]);
echo sprintf(
    'Всего работ: %d, общая стоимость: %s',
    count($rows),
    number_format($totalPrice, 2, '.', ' ')
) . PHP_EOL;
