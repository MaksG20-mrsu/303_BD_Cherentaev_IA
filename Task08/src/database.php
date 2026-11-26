<?php

declare(strict_types=1);

/**
 * Работа с базой данных станции технического обслуживания (SQLite, PDO).
 * Все запросы - подготовленные, значения передаются только параметрами.
 */

/** Нарушение бизнес-правила: сообщение можно показать пользователю. */
class BusinessRuleException extends RuntimeException
{
}

/**
 * Открывает базу данных. Если файла базы нет, создаёт её из data/db_init.sql.
 */
function open_database(): PDO
{
    $isNewDatabase = !file_exists(DATABASE_PATH);

    $directory = dirname(DATABASE_PATH);
    if (!is_dir($directory)) {
        mkdir($directory, 0777, true);
    }

    $pdo = new PDO('sqlite:' . DATABASE_PATH, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA foreign_keys = ON');

    if ($isNewDatabase) {
        $initScript = file_get_contents(INIT_SCRIPT_PATH);
        if ($initScript === false) {
            throw new RuntimeException('Не найден файл ' . INIT_SCRIPT_PATH);
        }

        try {
            $pdo->exec($initScript);
        } catch (PDOException $exception) {
            // Не оставляем наполовину созданную базу.
            $pdo = null;
            if (file_exists(DATABASE_PATH)) {
                unlink(DATABASE_PATH);
            }
            throw $exception;
        }
    }

    return $pdo;
}

/** Открывает базу; при ошибке показывает страницу с сообщением и завершает работу. */
function connect_or_exit(): PDO
{
    try {
        return open_database();
    } catch (RuntimeException $exception) {
        http_response_code(500);
        echo '<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><title>Ошибка</title></head><body>'
            . '<h1>Не удалось подключиться к базе данных</h1><p>' . e($exception->getMessage()) . '</p>'
            . '<p>Проверьте, что в PHP включены расширения pdo_sqlite и sqlite3.</p></body></html>';
        exit;
    }
}

// ---------------------------------------------------------------- услуги

/**
 * Услуги, которые сейчас оказываются (для списков выбора).
 *
 * @return array<int, array<string, mixed>>
 */
function find_active_services(PDO $pdo): array
{
    $statement = $pdo->prepare(
        'SELECT id, name, duration_min, price FROM services WHERE is_active = 1 ORDER BY name'
    );
    $statement->execute();

    return $statement->fetchAll();
}

/** Возвращает действующую услугу по номеру или null. */
function find_service(PDO $pdo, int $serviceId): ?array
{
    $statement = $pdo->prepare(
        'SELECT id, name, duration_min, price FROM services WHERE id = :id AND is_active = 1'
    );
    $statement->execute(['id' => $serviceId]);
    $service = $statement->fetch();

    return $service === false ? null : $service;
}

// ---------------------------------------------------------------- мастера

/**
 * Все мастера с перечнем услуг, которые они выполняют.
 *
 * @return array<int, array<string, mixed>>
 */
function find_masters_with_services(PDO $pdo): array
{
    $statement = $pdo->prepare(
        "SELECT m.id,
                m.last_name || ' ' || m.first_name || COALESCE(' ' || m.middle_name, '') AS full_name,
                m.phone,
                m.hire_date,
                m.dismissal_date,
                m.salary_percent,
                COALESCE(GROUP_CONCAT(s.name, ', '), '') AS services
         FROM masters AS m
         LEFT JOIN master_services AS ms ON ms.master_id = m.id
         LEFT JOIN services AS s ON s.id = ms.service_id
         GROUP BY m.id
         ORDER BY m.last_name, m.id"
    );
    $statement->execute();

    return $statement->fetchAll();
}

/**
 * Мастера, работающие на станции в указанную дату (приняты и ещё не уволены).
 *
 * @return array<int, array{id: int|string, full_name: string}>
 */
function find_masters_employed_on(PDO $pdo, string $date): array
{
    $statement = $pdo->prepare(
        "SELECT id,
                last_name || ' ' || first_name || COALESCE(' ' || middle_name, '') AS full_name
         FROM masters
         WHERE hire_date <= :hire_date
           AND (dismissal_date IS NULL OR dismissal_date >= :dismissal_date)
         ORDER BY last_name, id"
    );
    $statement->execute(['hire_date' => $date, 'dismissal_date' => $date]);

    return $statement->fetchAll();
}

/** Проверяет, что мастер с таким телефоном уже есть в базе. */
function phone_is_taken(PDO $pdo, string $phone): bool
{
    $statement = $pdo->prepare('SELECT COUNT(*) FROM masters WHERE phone = :phone');
    $statement->execute(['phone' => $phone]);

    return (int) $statement->fetchColumn() > 0;
}

/**
 * Добавляет мастера и привязывает к нему услуги, которые он может выполнять.
 *
 * @param array<string, string> $master     last_name, first_name, middle_name, phone, hire_date, salary_percent
 * @param int[]                 $serviceIds номера услуг
 *
 * @return int номер нового мастера
 */
function create_master(PDO $pdo, array $master, array $serviceIds): int
{
    $pdo->beginTransaction();

    try {
        $statement = $pdo->prepare(
            'INSERT INTO masters (last_name, first_name, middle_name, phone, hire_date, salary_percent)
             VALUES (:last_name, :first_name, :middle_name, :phone, :hire_date, :salary_percent)'
        );
        $statement->execute([
            'last_name' => $master['last_name'],
            'first_name' => $master['first_name'],
            'middle_name' => $master['middle_name'] === '' ? null : $master['middle_name'],
            'phone' => $master['phone'],
            'hire_date' => $master['hire_date'],
            'salary_percent' => $master['salary_percent'],
        ]);
        $masterId = (int) $pdo->lastInsertId();

        $link = $pdo->prepare(
            'INSERT INTO master_services (master_id, service_id) VALUES (:master_id, :service_id)'
        );
        foreach ($serviceIds as $serviceId) {
            $link->execute(['master_id' => $masterId, 'service_id' => $serviceId]);
        }

        $pdo->commit();

        return $masterId;
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }
}

// ---------------------------------------------------------------- график работы

/**
 * Ближайшие смены мастеров начиная с указанной даты.
 *
 * @return array<int, array<string, mixed>>
 */
function find_upcoming_schedule(PDO $pdo, string $fromDate, int $limit): array
{
    $statement = $pdo->prepare(
        "SELECT s.work_date, s.start_time, s.end_time,
                m.last_name || ' ' || m.first_name || COALESCE(' ' || m.middle_name, '') AS master_full_name
         FROM schedules AS s
         JOIN masters AS m ON m.id = s.master_id
         WHERE s.work_date >= :from_date
         ORDER BY s.work_date, m.last_name, m.id
         LIMIT " . $limit
    );
    $statement->execute(['from_date' => $fromDate]);

    return $statement->fetchAll();
}

/** Проверяет, задана ли уже смена мастера на эту дату. */
function schedule_exists(PDO $pdo, int $masterId, string $workDate): bool
{
    $statement = $pdo->prepare(
        'SELECT COUNT(*) FROM schedules WHERE master_id = :master_id AND work_date = :work_date'
    );
    $statement->execute(['master_id' => $masterId, 'work_date' => $workDate]);

    return (int) $statement->fetchColumn() > 0;
}

/** Добавляет смену в график мастера. */
function create_schedule(PDO $pdo, int $masterId, string $workDate, string $startTime, string $endTime): void
{
    $statement = $pdo->prepare(
        'INSERT INTO schedules (master_id, work_date, start_time, end_time)
         VALUES (:master_id, :work_date, :start_time, :end_time)'
    );
    $statement->execute([
        'master_id' => $masterId,
        'work_date' => $workDate,
        'start_time' => $startTime,
        'end_time' => $endTime,
    ]);
}

// ---------------------------------------------------------------- предварительная запись

/**
 * Мастера, которые выполняют услугу и работают на станции в указанную дату или позже.
 *
 * @return array<int, array{id: int|string, full_name: string}>
 */
function find_masters_for_service(PDO $pdo, int $serviceId, string $today): array
{
    $statement = $pdo->prepare(
        "SELECT m.id,
                m.last_name || ' ' || m.first_name || COALESCE(' ' || m.middle_name, '') AS full_name
         FROM masters AS m
         JOIN master_services AS ms ON ms.master_id = m.id
         WHERE ms.service_id = :service_id
           AND m.hire_date <= :hire_date
           AND (m.dismissal_date IS NULL OR m.dismissal_date >= :dismissal_date)
         ORDER BY m.last_name, m.id"
    );
    $statement->execute([
        'service_id' => $serviceId,
        'hire_date' => $today,
        'dismissal_date' => $today,
    ]);

    return $statement->fetchAll();
}

/**
 * Рабочие дни мастера (из его графика) начиная с указанной даты.
 *
 * @return array<int, array{work_date: string, start_time: string, end_time: string}>
 */
function find_master_working_days(PDO $pdo, int $masterId, string $fromDate): array
{
    $statement = $pdo->prepare(
        'SELECT s.work_date, s.start_time, s.end_time
         FROM schedules AS s
         JOIN masters AS m ON m.id = s.master_id
         WHERE s.master_id = :master_id
           AND s.work_date >= :from_date
           AND (m.dismissal_date IS NULL OR s.work_date <= m.dismissal_date)
         ORDER BY s.work_date
         LIMIT 60'
    );
    $statement->execute(['master_id' => $masterId, 'from_date' => $fromDate]);

    return $statement->fetchAll();
}

/**
 * Свободное время мастера в указанный день для услуги заданной длительности.
 * Время начала берётся с шагом SLOT_STEP_MINUTES внутри смены мастера; интервал
 * не должен пересекаться с его действующими записями. Для сегодняшнего дня
 * прошедшее время не предлагается.
 *
 * @return string[] время начала в формате ЧЧ:ММ
 */
function find_available_slots(
    PDO $pdo,
    int $masterId,
    string $date,
    int $durationMinutes,
    DateTimeImmutable $now
): array {
    $statement = $pdo->prepare(
        'SELECT start_time, end_time FROM schedules WHERE master_id = :master_id AND work_date = :work_date'
    );
    $statement->execute(['master_id' => $masterId, 'work_date' => $date]);
    $shift = $statement->fetch();
    if ($shift === false) {
        return [];
    }

    $statement = $pdo->prepare(
        "SELECT start_at, end_at
         FROM appointments
         WHERE master_id = :master_id
           AND status <> 'cancelled'
           AND start_at >= :day_start
           AND start_at <= :day_end"
    );
    $statement->execute([
        'master_id' => $masterId,
        'day_start' => $date . ' 00:00',
        'day_end' => $date . ' 23:59',
    ]);

    $busyIntervals = [];
    foreach ($statement->fetchAll() as $appointment) {
        $busyIntervals[] = [
            time_to_minutes(substr($appointment['start_at'], 11, 5)),
            time_to_minutes(substr($appointment['end_at'], 11, 5)),
        ];
    }

    // Для сегодняшнего дня время начала должно быть позже текущего момента.
    $earliestStart = -1;
    if ($date === $now->format('Y-m-d')) {
        $earliestStart = time_to_minutes($now->format('H:i'));
    }

    $shiftEnd = time_to_minutes($shift['end_time']);
    $slots = [];
    for ($start = time_to_minutes($shift['start_time']); $start + $durationMinutes <= $shiftEnd; $start += SLOT_STEP_MINUTES) {
        if ($start <= $earliestStart) {
            continue;
        }

        $end = $start + $durationMinutes;
        $isFree = true;
        foreach ($busyIntervals as $interval) {
            if ($interval[0] < $end && $interval[1] > $start) {
                $isFree = false;
                break;
            }
        }

        if ($isFree) {
            $slots[] = minutes_to_time($start);
        }
    }

    return $slots;
}

/** Ищет клиента по телефону, при отсутствии добавляет нового. Возвращает номер клиента. */
function find_or_create_client(PDO $pdo, array $client): int
{
    $statement = $pdo->prepare('SELECT id FROM clients WHERE phone = :phone');
    $statement->execute(['phone' => $client['phone']]);
    $clientId = $statement->fetchColumn();
    if ($clientId !== false) {
        return (int) $clientId;
    }

    $statement = $pdo->prepare(
        'INSERT INTO clients (last_name, first_name, phone) VALUES (:last_name, :first_name, :phone)'
    );
    $statement->execute([
        'last_name' => $client['last_name'],
        'first_name' => $client['first_name'],
        'phone' => $client['phone'],
    ]);

    return (int) $pdo->lastInsertId();
}

/** Ищет автомобиль по госномеру, при отсутствии добавляет новый. Возвращает номер автомобиля. */
function find_or_create_car(PDO $pdo, int $clientId, array $car): int
{
    $statement = $pdo->prepare('SELECT id, client_id FROM cars WHERE license_plate = :license_plate');
    $statement->execute(['license_plate' => $car['license_plate']]);
    $existing = $statement->fetch();

    if ($existing !== false) {
        if ((int) $existing['client_id'] !== $clientId) {
            throw new BusinessRuleException('Автомобиль с таким госномером уже зарегистрирован на другого клиента.');
        }

        return (int) $existing['id'];
    }

    $statement = $pdo->prepare(
        'INSERT INTO cars (client_id, license_plate, brand, model, year)
         VALUES (:client_id, :license_plate, :brand, :model, :year)'
    );
    $statement->execute([
        'client_id' => $clientId,
        'license_plate' => $car['license_plate'],
        'brand' => $car['brand'],
        'model' => $car['model'],
        'year' => $car['year'],
    ]);

    return (int) $pdo->lastInsertId();
}

/**
 * Создаёт предварительную запись: клиент и автомобиль добавляются при необходимости.
 * Всё выполняется в одной транзакции. Занятость мастера дополнительно контролируют
 * триггеры базы данных.
 *
 * @param array<string, string>   $client last_name, first_name, phone
 * @param array<string, mixed>    $car    license_plate, brand, model, year (int или null)
 *
 * @return int номер новой записи
 */
function create_appointment(
    PDO $pdo,
    array $client,
    array $car,
    int $masterId,
    int $serviceId,
    string $startAt,
    string $endAt
): int {
    $pdo->beginTransaction();

    try {
        $clientId = find_or_create_client($pdo, $client);
        $carId = find_or_create_car($pdo, $clientId, $car);

        $statement = $pdo->prepare(
            "INSERT INTO appointments (car_id, master_id, start_at, end_at, status)
             VALUES (:car_id, :master_id, :start_at, :end_at, 'booked')"
        );
        $statement->execute([
            'car_id' => $carId,
            'master_id' => $masterId,
            'start_at' => $startAt,
            'end_at' => $endAt,
        ]);
        $appointmentId = (int) $pdo->lastInsertId();

        $statement = $pdo->prepare(
            'INSERT INTO appointment_services (appointment_id, service_id) VALUES (:appointment_id, :service_id)'
        );
        $statement->execute(['appointment_id' => $appointmentId, 'service_id' => $serviceId]);

        $pdo->commit();

        return $appointmentId;
    } catch (Throwable $exception) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $exception;
    }
}

/** Краткие сведения о записи для страницы подтверждения; null, если записи нет. */
function find_appointment_summary(PDO $pdo, int $appointmentId): ?array
{
    $statement = $pdo->prepare(
        "SELECT a.id, a.start_at, a.end_at,
                s.name AS service_name,
                m.last_name || ' ' || m.first_name || COALESCE(' ' || m.middle_name, '') AS master_full_name,
                c.license_plate
         FROM appointments AS a
         JOIN appointment_services AS x ON x.appointment_id = a.id
         JOIN services AS s ON s.id = x.service_id
         JOIN masters AS m ON m.id = a.master_id
         JOIN cars AS c ON c.id = a.car_id
         WHERE a.id = :id"
    );
    $statement->execute(['id' => $appointmentId]);
    $summary = $statement->fetch();

    return $summary === false ? null : $summary;
}
