<?php

declare(strict_types=1);

/**
 * Лабораторная работа 7, часть 2.
 * Веб-страница со списком услуг, оказанных мастерами СТО, с фильтром по мастеру.
 *
 * Запуск: php -S localhost:8000 (из каталога Task07), затем открыть http://localhost:8000/
 *
 * Сначала собираются данные, ниже идёт HTML-шаблон: в нём нет вызовов echo,
 * значения выводятся короткой записью тега вывода, а управляющие конструкции
 * записаны в альтернативном синтаксисе (if: ... endif; foreach: ... endforeach;).
 */

require __DIR__ . '/database.php';

/** Экранирует строку для безопасной вставки в HTML. */
function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES, 'UTF-8');
}

$masters = [];
$works = [];
$selectedMasterId = null;
$errorMessage = null;
$warningMessage = null;

try {
    $pdo = open_database();
    $masters = find_all_masters($pdo);
    $availableIds = array_map(
        fn(array $master): int => (int) $master['id'],
        $masters
    );

    // Фильтр: пустое значение - все мастера, иначе номер должен быть в списке из базы.
    $rawMasterId = $_GET['master_id'] ?? '';
    if ($rawMasterId !== '') {
        $candidateId = is_string($rawMasterId) ? filter_var($rawMasterId, FILTER_VALIDATE_INT) : false;
        if ($candidateId !== false && in_array($candidateId, $availableIds, true)) {
            $selectedMasterId = $candidateId;
        } else {
            $warningMessage = 'Мастера с таким номером нет, показаны работы всех мастеров.';
        }
    }

    $works = find_performed_works($pdo, $selectedMasterId);
} catch (RuntimeException $exception) { // PDOException тоже наследует RuntimeException
    $errorMessage = 'Не удалось получить данные из базы: ' . $exception->getMessage();
}

$totalPrice = array_sum(array_map(
    fn(array $work): float => (float) $work['price'],
    $works
));
?>
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Выполненные работы мастеров СТО</title>
    <style>
        body { font-family: Arial, Helvetica, sans-serif; margin: 2rem auto; max-width: 960px; padding: 0 1rem; color: #222; }
        h1 { font-size: 1.5rem; }
        .filter { margin: 1rem 0; }
        .filter select, .filter button { font-size: 1rem; padding: 0.25rem 0.5rem; }
        .message { padding: 0.6rem 0.9rem; border-radius: 4px; }
        .message-error { background: #fde8e8; color: #8a1f1f; }
        .message-warning { background: #fff4d6; color: #7a5a00; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #b8c2cc; padding: 0.4rem 0.7rem; text-align: left; }
        th { background: #5b7fa6; color: #fff; }
        tbody tr:nth-child(even) { background: #f3f6f9; }
        .number { text-align: right; white-space: nowrap; }
        tfoot td { font-weight: bold; background: #e6edf4; }
    </style>
</head>
<body>
    <h1>Выполненные работы мастеров СТО</h1>

    <?php if ($errorMessage !== null): ?>
        <p class="message message-error"><?= e($errorMessage) ?></p>
    <?php else: ?>
        <form class="filter" method="get" action="index.php">
            <label for="master_id">Мастер:</label>
            <select name="master_id" id="master_id">
                <option value="">Все мастера</option>
                <?php foreach ($masters as $master): ?>
                    <option value="<?= e((string) $master['id']) ?>"<?php if ($selectedMasterId === (int) $master['id']): ?> selected<?php endif; ?>>
                        <?= e((string) $master['id']) ?> - <?= e($master['full_name']) ?><?php if ((int) $master['is_dismissed'] === 1): ?> (уволен)<?php endif; ?>
                    </option>
                <?php endforeach; ?>
            </select>
            <button type="submit">Показать</button>
        </form>

        <?php if ($warningMessage !== null): ?>
            <p class="message message-warning"><?= e($warningMessage) ?></p>
        <?php endif; ?>

        <?php if (count($works) === 0): ?>
            <p>Выполненных работ не найдено.</p>
        <?php else: ?>
            <table>
                <thead>
                    <tr>
                        <th>Номер мастера</th>
                        <th>ФИО</th>
                        <th>Дата работы</th>
                        <th>Услуга</th>
                        <th class="number">Стоимость, руб.</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($works as $work): ?>
                        <tr>
                            <td><?= e((string) $work['master_id']) ?></td>
                            <td><?= e($work['master_full_name']) ?></td>
                            <td><?= e($work['work_date']) ?></td>
                            <td><?= e($work['service_name']) ?></td>
                            <td class="number"><?= e(number_format((float) $work['price'], 2, '.', ' ')) ?></td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
                <tfoot>
                    <tr>
                        <td colspan="4">Всего работ: <?= count($works) ?></td>
                        <td class="number"><?= e(number_format($totalPrice, 2, '.', ' ')) ?></td>
                    </tr>
                </tfoot>
            </table>
        <?php endif; ?>
    <?php endif; ?>
</body>
</html>
