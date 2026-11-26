<?php

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$pdo = connect_or_exit();
$today = (new DateTimeImmutable('now'))->format('Y-m-d');

$values = [
    'master_id' => '',
    'work_date' => $today,
    'start_time' => '09:00',
    'end_time' => '18:00',
];
$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach (array_keys($values) as $field) {
        $values[$field] = read_text($_POST, $field);
    }

    // Мастер должен работать на станции в выбранную дату.
    $employedMasterIds = [];
    if (is_valid_date($values['work_date'])) {
        foreach (find_masters_employed_on($pdo, $values['work_date']) as $employedMaster) {
            $employedMasterIds[] = (int) $employedMaster['id'];
        }
    }

    $errors = validate_schedule_input($pdo, $values, $employedMasterIds);

    if (count($errors) === 0) {
        try {
            create_schedule($pdo, (int) $values['master_id'], $values['work_date'], $values['start_time'], $values['end_time']);
            redirect('schedule_form.php?saved=1');
        } catch (RuntimeException $exception) {
            $errors['form'] = 'Не удалось сохранить смену. Проверьте данные и попробуйте ещё раз.';
        }
    }
}

$isSaved = $_SERVER['REQUEST_METHOD'] !== 'POST' && read_text($_GET, 'saved') === '1';
$masters = find_masters_employed_on($pdo, $today);
$upcomingShifts = find_upcoming_schedule($pdo, $today, 40);

$pageTitle = 'График работы мастеров';
require __DIR__ . '/../templates/header.php';
?>
    <?php if ($isSaved): ?>
        <p class="message message-success">Смена добавлена в график.</p>
    <?php endif; ?>

    <?php if (count($errors) > 0): ?>
        <div class="message message-error">
            Данные не сохранены, исправьте ошибки:
            <ul>
                <?php foreach ($errors as $error): ?>
                    <li><?= e($error) ?></li>
                <?php endforeach; ?>
            </ul>
        </div>
    <?php endif; ?>

    <form method="post" action="schedule_form.php">
        <div class="field">
            <label for="master_id">Мастер *</label>
            <select id="master_id" name="master_id" required>
                <option value="">- выберите мастера -</option>
                <?php foreach ($masters as $master): ?>
                    <option value="<?= e((string) $master['id']) ?>"<?php if ($values['master_id'] === (string) $master['id']): ?> selected<?php endif; ?>>
                        <?= e($master['full_name']) ?>
                    </option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="field">
            <label for="work_date">Дата *</label>
            <input type="date" id="work_date" name="work_date" required value="<?= e($values['work_date']) ?>">
        </div>
        <div class="field">
            <label for="start_time">Начало смены *</label>
            <input type="time" id="start_time" name="start_time" required value="<?= e($values['start_time']) ?>">
        </div>
        <div class="field">
            <label for="end_time">Конец смены *</label>
            <input type="time" id="end_time" name="end_time" required value="<?= e($values['end_time']) ?>">
        </div>
        <button type="submit">Добавить смену</button>
    </form>

    <h2>Ближайшие смены</h2>
    <?php if (count($upcomingShifts) === 0): ?>
        <p class="muted">В графике нет смен, начиная с сегодняшнего дня.</p>
    <?php else: ?>
        <table>
            <thead>
                <tr>
                    <th>Дата</th>
                    <th>Мастер</th>
                    <th>Начало</th>
                    <th>Конец</th>
                </tr>
            </thead>
            <tbody>
                <?php foreach ($upcomingShifts as $shift): ?>
                    <tr>
                        <td><?= e(format_date_with_weekday($shift['work_date'])) ?></td>
                        <td><?= e($shift['master_full_name']) ?></td>
                        <td><?= e($shift['start_time']) ?></td>
                        <td><?= e($shift['end_time']) ?></td>
                    </tr>
                <?php endforeach; ?>
            </tbody>
        </table>
    <?php endif; ?>
<?php require __DIR__ . '/../templates/footer.php'; ?>
