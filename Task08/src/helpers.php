<?php

declare(strict_types=1);

/**
 * Вспомогательные функции: экранирование, чтение полей формы, работа с датой и временем.
 */

/** Экранирует строку для безопасной вставки в HTML. */
function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

/** Выполняет перенаправление и завершает работу сценария. */
function redirect(string $location): void
{
    header('Location: ' . $location);
    exit;
}

/** Число символов в UTF-8 строке (не требует расширения mbstring). */
function text_length(string $text): int
{
    return (int) preg_match_all('/./su', $text);
}

/** Читает текстовое поле из $_GET/$_POST: строка без пробелов по краям или пустая строка. */
function read_text(array $source, string $key): string
{
    $value = $source[$key] ?? '';

    return is_string($value) ? trim($value) : '';
}

/** Читает целое неотрицательное число из поля формы; при ошибке возвращает null. */
function read_int(array $source, string $key): ?int
{
    $value = read_text($source, $key);
    if (preg_match('/^\d{1,9}$/', $value) !== 1) {
        return null;
    }

    return (int) $value;
}

/**
 * Читает список целых чисел (например, отмеченные флажки name="service_ids[]").
 *
 * @return int[]
 */
function read_int_list(array $source, string $key): array
{
    $values = $source[$key] ?? [];
    if (!is_array($values)) {
        return [];
    }

    $result = [];
    foreach ($values as $value) {
        if (is_string($value) && preg_match('/^\d{1,9}$/', $value) === 1) {
            $result[] = (int) $value;
        }
    }

    return array_values(array_unique($result));
}

/** Проверяет, что строка - существующая дата в формате ГГГГ-ММ-ДД. */
function is_valid_date(string $value): bool
{
    $date = DateTimeImmutable::createFromFormat('!Y-m-d', $value);

    return $date !== false && $date->format('Y-m-d') === $value;
}

/** Проверяет, что строка - время в формате ЧЧ:ММ. */
function is_valid_time(string $value): bool
{
    $time = DateTimeImmutable::createFromFormat('!H:i', $value);

    return $time !== false && $time->format('H:i') === $value;
}

/** Переводит время ЧЧ:ММ в минуты от начала суток. */
function time_to_minutes(string $time): int
{
    return ((int) substr($time, 0, 2)) * 60 + (int) substr($time, 3, 2);
}

/** Переводит минуты от начала суток во время ЧЧ:ММ. */
function minutes_to_time(int $minutes): string
{
    return sprintf('%02d:%02d', intdiv($minutes, 60), $minutes % 60);
}

/** Дата для показа пользователю: 01.12.2026 (вт). */
function format_date_with_weekday(string $date): string
{
    $weekdays = [1 => 'пн', 2 => 'вт', 3 => 'ср', 4 => 'чт', 5 => 'пт', 6 => 'сб', 7 => 'вс'];
    $parsed = DateTimeImmutable::createFromFormat('!Y-m-d', $date);
    if ($parsed === false) {
        return $date;
    }

    return $parsed->format('d.m.Y') . ' (' . $weekdays[(int) $parsed->format('N')] . ')';
}

/** Дата и время для показа пользователю: из ГГГГ-ММ-ДД ЧЧ:ММ в ДД.ММ.ГГГГ ЧЧ:ММ. */
function format_datetime(string $dateTime): string
{
    $parsed = DateTimeImmutable::createFromFormat('!Y-m-d H:i', $dateTime);

    return $parsed === false ? $dateTime : $parsed->format('d.m.Y H:i');
}

/** Денежная сумма для показа пользователю. */
function format_money(float $amount): string
{
    return number_format($amount, 2, '.', ' ');
}

/**
 * Приводит госномер к единому виду: без пробелов и в верхнем регистре
 * (в том числе для кириллицы, без расширения mbstring).
 */
function normalize_license_plate(string $plate): string
{
    $plate = (string) preg_replace('/\s+/u', '', $plate);
    $lower = preg_split('//u', 'абвгдеёжзийклмнопрстуфхцчшщъыьэюя', -1, PREG_SPLIT_NO_EMPTY);
    $upper = preg_split('//u', 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ', -1, PREG_SPLIT_NO_EMPTY);

    return strtr(strtoupper($plate), array_combine($lower, $upper));
}
