<?php

declare(strict_types=1);

/**
 * Предварительная запись к мастеру. Выбор идёт по шагам:
 * услуга -> мастер (только те, кто выполняет эту услугу) -> дата и свободное время.
 * Шаги выбора отправляются методом GET (страница перерисовывается), а сама запись
 * сохраняется методом POST после ввода данных клиента и автомобиля.
 */

require __DIR__ . '/../src/bootstrap.php';

$pdo = connect_or_exit();
$now = new DateTimeImmutable('now');
$today = $now->format('Y-m-d');
$isPost = $_SERVER['REQUEST_METHOD'] === 'POST';
$input = $isPost ? $_POST : $_GET;

// Шаг 1. Услуга.
$services = find_active_services($pdo);
$serviceId = read_int($input, 'service_id');
$service = $serviceId !== null ? find_service($pdo, $serviceId) : null;

// Шаг 2. Мастер: только тот, кто выполняет выбранную услугу.
$masters = $service !== null ? find_masters_for_service($pdo, (int) $service['id'], $today) : [];
$masterId = read_int($input, 'master_id');
$master = null;
foreach ($masters as $candidate) {
    if ($masterId !== null && (int) $candidate['id'] === $masterId) {
        $master = $candidate;
    }
}

// Шаг 3. Дата из графика мастера и свободное время в этот день.
$workingDays = $master !== null ? find_master_working_days($pdo, (int) $master['id'], $today) : [];
$requestedDate = read_text($input, 'date');
$selectedDate = null;
foreach ($workingDays as $workingDay) {
    if ($workingDay['work_date'] === $requestedDate) {
        $selectedDate = $requestedDate;
    }
}

$slots = [];
if ($service !== null && $master !== null && $selectedDate !== null) {
    $slots = find_available_slots($pdo, (int) $master['id'], $selectedDate, (int) $service['duration_min'], $now);
}

// Шаг 4. Данные клиента и автомобиля, сохранение записи.
$clientFields = ['client_last_name', 'client_first_name', 'client_phone', 'car_plate', 'car_brand', 'car_model', 'car_year'];
$values = array_fill_keys($clientFields, '');
$selectedTime = '';
$errors = [];

if ($isPost) {
    foreach ($clientFields as $field) {
        $values[$field] = read_text($_POST, $field);
    }
    $selectedTime = read_text($_POST, 'time');

    if ($service === null) {
        $errors['service_id'] = 'Выберите услугу.';
    } elseif ($master === null) {
        $errors['master_id'] = 'Выберите мастера из списка.';
    } elseif ($selectedDate === null) {
        $errors['date'] = 'Выберите дату из списка.';
    } elseif (!in_array($selectedTime, $slots, true)) {
        $errors['time'] = 'Выбранное время недоступно, выберите другое.';
    }

    $errors = array_merge($errors, validate_appointment_client_input($values));

    if (count($errors) === 0) {
        $startAt = $selectedDate . ' ' . $selectedTime;
        $endAt = $selectedDate . ' ' . minutes_to_time(time_to_minutes($selectedTime) + (int) $service['duration_min']);

        $client = [
            'last_name' => $values['client_last_name'],
            'first_name' => $values['client_first_name'],
            'phone' => $values['client_phone'],
        ];
        $car = [
            'license_plate' => normalize_license_plate($values['car_plate']),
            'brand' => $values['car_brand'],
            'model' => $values['car_model'],
            'year' => $values['car_year'] === '' ? null : (int) $values['car_year'],
        ];

        try {
            $appointmentId = create_appointment($pdo, $client, $car, (int) $master['id'], (int) $service['id'], $startAt, $endAt);
            redirect('appointment_form.php?booked=' . $appointmentId);
        } catch (BusinessRuleException $exception) {
            $errors['form'] = $exception->getMessage();
        } catch (RuntimeException $exception) {
            $errors['form'] = 'Не удалось создать запись: возможно, это время уже занято. Выберите другое время.';
        }
    }
}

// Подтверждение после успешной записи.
$bookedAppointment = null;
if (!$isPost) {
    $bookedId = read_int($_GET, 'booked');
    if ($bookedId !== null) {
        $bookedAppointment = find_appointment_summary($pdo, $bookedId);
    }
}

$pageTitle = 'Предварительная запись';
require __DIR__ . '/../templates/header.php';
?>
    <?php if ($bookedAppointment !== null): ?>
        <div class="message message-success">
            Запись №<?= e((string) $bookedAppointment['id']) ?> создана:
            <?= e($bookedAppointment['service_name']) ?>, мастер <?= e($bookedAppointment['master_full_name']) ?>,
            <?= e(format_datetime($bookedAppointment['start_at'])) ?> - <?= e(substr($bookedAppointment['end_at'], 11, 5)) ?>,
            автомобиль <?= e($bookedAppointment['license_plate']) ?>.
        </div>
    <?php endif; ?>

    <?php if (count($errors) > 0): ?>
        <div class="message message-error">
            Запись не создана, исправьте ошибки:
            <ul>
                <?php foreach ($errors as $error): ?>
                    <li><?= e($error) ?></li>
                <?php endforeach; ?>
            </ul>
        </div>
    <?php endif; ?>

    <form method="get" action="appointment_form.php">
        <div class="field">
            <label for="service_id">1. Услуга</label>
            <select id="service_id" name="service_id" onchange="this.form.submit()">
                <option value="">- выберите услугу -</option>
                <?php foreach ($services as $serviceOption): ?>
                    <option value="<?= e((string) $serviceOption['id']) ?>"<?php if ($service !== null && (int) $service['id'] === (int) $serviceOption['id']): ?> selected<?php endif; ?>>
                        <?= e($serviceOption['name']) ?>
                        (<?= e((string) $serviceOption['duration_min']) ?> мин, <?= e(format_money((float) $serviceOption['price'])) ?> руб.)
                    </option>
                <?php endforeach; ?>
            </select>
        </div>

        <?php if ($service !== null): ?>
            <div class="field">
                <label for="master_id">2. Мастер</label>
                <?php if (count($masters) === 0): ?>
                    <p class="message message-warning">Сейчас нет мастеров, которые выполняют эту услугу.</p>
                <?php else: ?>
                    <select id="master_id" name="master_id" onchange="this.form.submit()">
                        <option value="">- выберите мастера -</option>
                        <?php foreach ($masters as $masterOption): ?>
                            <option value="<?= e((string) $masterOption['id']) ?>"<?php if ($master !== null && (int) $master['id'] === (int) $masterOption['id']): ?> selected<?php endif; ?>>
                                <?= e($masterOption['full_name']) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                <?php endif; ?>
            </div>
        <?php endif; ?>

        <?php if ($master !== null): ?>
            <div class="field">
                <label for="date">3. Дата</label>
                <?php if (count($workingDays) === 0): ?>
                    <p class="message message-warning">В графике мастера нет рабочих дней. Добавьте смены на странице «График работы».</p>
                <?php else: ?>
                    <select id="date" name="date" onchange="this.form.submit()">
                        <option value="">- выберите дату -</option>
                        <?php foreach ($workingDays as $workingDay): ?>
                            <option value="<?= e($workingDay['work_date']) ?>"<?php if ($selectedDate === $workingDay['work_date']): ?> selected<?php endif; ?>>
                                <?= e(format_date_with_weekday($workingDay['work_date'])) ?>, смена <?= e($workingDay['start_time']) ?>-<?= e($workingDay['end_time']) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                <?php endif; ?>
            </div>
        <?php endif; ?>

        <noscript><button type="submit">Далее</button></noscript>
    </form>

    <?php if ($service !== null && $master !== null && $selectedDate !== null): ?>
        <?php if (count($slots) === 0): ?>
            <p class="message message-warning">На эту дату у мастера нет свободного времени для выбранной услуги. Выберите другую дату.</p>
        <?php else: ?>
            <form method="post" action="appointment_form.php">
                <input type="hidden" name="service_id" value="<?= e((string) $service['id']) ?>">
                <input type="hidden" name="master_id" value="<?= e((string) $master['id']) ?>">
                <input type="hidden" name="date" value="<?= e($selectedDate) ?>">

                <div class="field">
                    <label for="time">4. Свободное время *</label>
                    <select id="time" name="time" required>
                        <option value="">- выберите время -</option>
                        <?php foreach ($slots as $slot): ?>
                            <option value="<?= e($slot) ?>"<?php if ($selectedTime === $slot): ?> selected<?php endif; ?>>
                                <?= e($slot) ?> - <?= e(minutes_to_time(time_to_minutes($slot) + (int) $service['duration_min'])) ?>
                            </option>
                        <?php endforeach; ?>
                    </select>
                    <span class="hint">Показано время начала и окончания работы (<?= e((string) $service['duration_min']) ?> мин).</span>
                </div>

                <div class="field">
                    <label for="client_last_name">Фамилия клиента *</label>
                    <input type="text" id="client_last_name" name="client_last_name" maxlength="50" required value="<?= e($values['client_last_name']) ?>">
                </div>
                <div class="field">
                    <label for="client_first_name">Имя клиента *</label>
                    <input type="text" id="client_first_name" name="client_first_name" maxlength="50" required value="<?= e($values['client_first_name']) ?>">
                </div>
                <div class="field">
                    <label for="client_phone">Телефон клиента *</label>
                    <input type="tel" id="client_phone" name="client_phone" maxlength="20" required placeholder="+7 937 123-45-67" value="<?= e($values['client_phone']) ?>">
                </div>
                <div class="field">
                    <label for="car_plate">Госномер автомобиля *</label>
                    <input type="text" id="car_plate" name="car_plate" maxlength="12" required placeholder="А123ВС13" value="<?= e($values['car_plate']) ?>">
                </div>
                <div class="field">
                    <label for="car_brand">Марка *</label>
                    <input type="text" id="car_brand" name="car_brand" maxlength="50" required value="<?= e($values['car_brand']) ?>">
                </div>
                <div class="field">
                    <label for="car_model">Модель *</label>
                    <input type="text" id="car_model" name="car_model" maxlength="50" required value="<?= e($values['car_model']) ?>">
                </div>
                <div class="field">
                    <label for="car_year">Год выпуска</label>
                    <input type="number" id="car_year" name="car_year" min="1950" max="2100" value="<?= e($values['car_year']) ?>">
                </div>

                <button type="submit">Записаться</button>
            </form>
        <?php endif; ?>
    <?php endif; ?>
<?php require __DIR__ . '/../templates/footer.php'; ?>
