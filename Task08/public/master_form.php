<?php

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$pdo = connect_or_exit();
$today = (new DateTimeImmutable('now'))->format('Y-m-d');
$services = find_active_services($pdo);
$availableServiceIds = array_map(
    fn(array $service): int => (int) $service['id'],
    $services
);

$values = [
    'last_name' => '',
    'first_name' => '',
    'middle_name' => '',
    'phone' => '',
    'hire_date' => $today,
    'salary_percent' => '30',
];
$selectedServiceIds = [];
$errors = [];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    foreach (array_keys($values) as $field) {
        $values[$field] = read_text($_POST, $field);
    }
    $values['salary_percent'] = str_replace(',', '.', $values['salary_percent']);
    $selectedServiceIds = read_int_list($_POST, 'service_ids');

    $errors = validate_master_input($pdo, $values, $selectedServiceIds, $availableServiceIds);

    if (count($errors) === 0) {
        try {
            create_master($pdo, $values, $selectedServiceIds);
            redirect('master_form.php?saved=1');
        } catch (RuntimeException $exception) {
            $errors['form'] = 'Не удалось сохранить мастера. Проверьте данные и попробуйте ещё раз.';
        }
    }
}

$isSaved = $_SERVER['REQUEST_METHOD'] !== 'POST' && read_text($_GET, 'saved') === '1';
$masters = find_masters_with_services($pdo);

$pageTitle = 'Добавление мастера';
require __DIR__ . '/../templates/header.php';
?>
    <?php if ($isSaved): ?>
        <p class="message message-success">Мастер добавлен.</p>
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

    <form method="post" action="master_form.php">
        <div class="field">
            <label for="last_name">Фамилия *</label>
            <input type="text" id="last_name" name="last_name" maxlength="50" required value="<?= e($values['last_name']) ?>">
        </div>
        <div class="field">
            <label for="first_name">Имя *</label>
            <input type="text" id="first_name" name="first_name" maxlength="50" required value="<?= e($values['first_name']) ?>">
        </div>
        <div class="field">
            <label for="middle_name">Отчество</label>
            <input type="text" id="middle_name" name="middle_name" maxlength="50" value="<?= e($values['middle_name']) ?>">
        </div>
        <div class="field">
            <label for="phone">Телефон *</label>
            <input type="tel" id="phone" name="phone" maxlength="20" required placeholder="+7 927 123-45-67" value="<?= e($values['phone']) ?>">
        </div>
        <div class="field">
            <label for="hire_date">Дата приёма на работу *</label>
            <input type="date" id="hire_date" name="hire_date" required value="<?= e($values['hire_date']) ?>">
        </div>
        <div class="field">
            <label for="salary_percent">Процент от выручки *</label>
            <input type="text" id="salary_percent" name="salary_percent" inputmode="decimal" maxlength="6" required value="<?= e($values['salary_percent']) ?>">
            <span class="hint">Число от 0 до 100, например 35 или 38.5</span>
        </div>
        <div class="field">
            <span class="label">Услуги, которые выполняет мастер *</span>
            <?php foreach ($services as $service): ?>
                <label class="checkbox">
                    <input type="checkbox" name="service_ids[]" value="<?= e((string) $service['id']) ?>"<?php if (in_array((int) $service['id'], $selectedServiceIds, true)): ?> checked<?php endif; ?>>
                    <?= e($service['name']) ?>
                </label>
            <?php endforeach; ?>
        </div>
        <button type="submit">Сохранить мастера</button>
    </form>

    <h2>Мастера станции</h2>
    <table>
        <thead>
            <tr>
                <th>№</th>
                <th>ФИО</th>
                <th>Телефон</th>
                <th>Принят</th>
                <th>Статус</th>
                <th>Процент</th>
                <th>Услуги</th>
            </tr>
        </thead>
        <tbody>
            <?php foreach ($masters as $master): ?>
                <tr>
                    <td><?= e((string) $master['id']) ?></td>
                    <td><?= e($master['full_name']) ?></td>
                    <td><?= e($master['phone']) ?></td>
                    <td><?= e(format_date_with_weekday($master['hire_date'])) ?></td>
                    <td>
                        <?php if ($master['dismissal_date'] === null): ?>
                            работает
                        <?php else: ?>
                            уволен <?= e(format_date_with_weekday($master['dismissal_date'])) ?>
                        <?php endif; ?>
                    </td>
                    <td><?= e((string) $master['salary_percent']) ?>%</td>
                    <td><?= e($master['services']) ?></td>
                </tr>
            <?php endforeach; ?>
        </tbody>
    </table>
<?php require __DIR__ . '/../templates/footer.php'; ?>
