<?php

declare(strict_types=1);

/**
 * Проверка данных, введённых в формы. Каждая функция возвращает массив
 * «поле => текст ошибки»; пустой массив означает, что данные корректны.
 */

/** Имя, фамилия или отчество: буквы, пробелы, дефисы, апостроф; не длиннее 50 символов. */
function is_valid_person_name(string $value): bool
{
    return text_length($value) <= 50
        && preg_match('/^\p{L}[\p{L}\s\-\']*$/u', $value) === 1;
}

/** Телефон: цифры, плюс, пробелы, дефисы и скобки; от 10 до 15 цифр. */
function is_valid_phone(string $value): bool
{
    if (preg_match('/^\+?[0-9\s\-()]+$/', $value) !== 1) {
        return false;
    }

    $digitCount = strlen((string) preg_replace('/\D/', '', $value));

    return $digitCount >= 10 && $digitCount <= 15;
}

/** Марка или модель автомобиля: буквы, цифры, пробелы, дефисы и точки; не длиннее 50 символов. */
function is_valid_vehicle_text(string $value): bool
{
    return text_length($value) <= 50
        && preg_match('/^[\p{L}\d][\p{L}\d\s\-\.]*$/u', $value) === 1;
}

/**
 * Проверка формы добавления мастера.
 *
 * @param array<string, string> $values              last_name, first_name, middle_name, phone, hire_date, salary_percent
 * @param int[]                 $selectedServiceIds  отмеченные услуги
 * @param int[]                 $availableServiceIds номера услуг, существующих в справочнике
 *
 * @return array<string, string>
 */
function validate_master_input(PDO $pdo, array $values, array $selectedServiceIds, array $availableServiceIds): array
{
    $errors = [];

    $requiredNames = ['last_name' => 'Фамилия', 'first_name' => 'Имя'];
    foreach ($requiredNames as $field => $label) {
        if ($values[$field] === '') {
            $errors[$field] = $label . ': обязательное поле.';
        } elseif (!is_valid_person_name($values[$field])) {
            $errors[$field] = $label . ': допустимы только буквы, пробел и дефис (до 50 символов).';
        }
    }

    if ($values['middle_name'] !== '' && !is_valid_person_name($values['middle_name'])) {
        $errors['middle_name'] = 'Отчество: допустимы только буквы, пробел и дефис (до 50 символов).';
    }

    if ($values['phone'] === '') {
        $errors['phone'] = 'Телефон: обязательное поле.';
    } elseif (!is_valid_phone($values['phone'])) {
        $errors['phone'] = 'Телефон: укажите от 10 до 15 цифр, например +7 927 123-45-67.';
    } elseif (phone_is_taken($pdo, $values['phone'])) {
        $errors['phone'] = 'Мастер с таким телефоном уже есть в базе.';
    }

    if (!is_valid_date($values['hire_date'])) {
        $errors['hire_date'] = 'Дата приёма: укажите корректную дату.';
    }

    if (preg_match('/^\d{1,3}(\.\d{1,2})?$/', $values['salary_percent']) !== 1
        || (float) $values['salary_percent'] > 100
    ) {
        $errors['salary_percent'] = 'Процент от выручки: число от 0 до 100.';
    }

    if (count($selectedServiceIds) === 0) {
        $errors['service_ids'] = 'Отметьте хотя бы одну услугу, которую выполняет мастер.';
    } elseif (count(array_diff($selectedServiceIds, $availableServiceIds)) > 0) {
        $errors['service_ids'] = 'Выбрана услуга, которой нет в справочнике.';
    }

    return $errors;
}

/**
 * Проверка формы добавления смены в график.
 *
 * @param array<string, string> $values              master_id, work_date, start_time, end_time
 * @param int[]                 $employedMasterIds   мастера, работающие в выбранную дату
 *
 * @return array<string, string>
 */
function validate_schedule_input(PDO $pdo, array $values, array $employedMasterIds): array
{
    $errors = [];

    $masterId = preg_match('/^\d{1,9}$/', $values['master_id']) === 1 ? (int) $values['master_id'] : null;

    if (!is_valid_date($values['work_date'])) {
        $errors['work_date'] = 'Дата: укажите корректную дату.';
    }

    if ($masterId === null) {
        $errors['master_id'] = 'Выберите мастера.';
    } elseif (!in_array($masterId, $employedMasterIds, true)) {
        $errors['master_id'] = 'Этот мастер не работает на станции в выбранную дату (не принят или уволен).';
    }

    if (!is_valid_time($values['start_time'])) {
        $errors['start_time'] = 'Начало смены: укажите время в формате ЧЧ:ММ.';
    }
    if (!is_valid_time($values['end_time'])) {
        $errors['end_time'] = 'Конец смены: укажите время в формате ЧЧ:ММ.';
    }

    if (!isset($errors['start_time']) && !isset($errors['end_time']) && $values['end_time'] <= $values['start_time']) {
        $errors['end_time'] = 'Конец смены должен быть позже начала.';
    }

    if (!isset($errors['work_date']) && !isset($errors['master_id']) && schedule_exists($pdo, (int) $masterId, $values['work_date'])) {
        $errors['work_date'] = 'У этого мастера на выбранную дату уже есть смена.';
    }

    return $errors;
}

/**
 * Проверка данных клиента и его автомобиля в форме записи.
 *
 * @param array<string, string> $values client_last_name, client_first_name, client_phone,
 *                                      car_plate, car_brand, car_model, car_year
 *
 * @return array<string, string>
 */
function validate_appointment_client_input(array $values): array
{
    $errors = [];

    $names = ['client_last_name' => 'Фамилия', 'client_first_name' => 'Имя'];
    foreach ($names as $field => $label) {
        if ($values[$field] === '') {
            $errors[$field] = $label . ': обязательное поле.';
        } elseif (!is_valid_person_name($values[$field])) {
            $errors[$field] = $label . ': допустимы только буквы, пробел и дефис (до 50 символов).';
        }
    }

    if ($values['client_phone'] === '') {
        $errors['client_phone'] = 'Телефон: обязательное поле.';
    } elseif (!is_valid_phone($values['client_phone'])) {
        $errors['client_phone'] = 'Телефон: укажите от 10 до 15 цифр, например +7 927 123-45-67.';
    }

    $plate = normalize_license_plate($values['car_plate']);
    if ($plate === '') {
        $errors['car_plate'] = 'Госномер: обязательное поле.';
    } elseif (preg_match('/^[\p{L}\d]{4,12}$/u', $plate) !== 1) {
        $errors['car_plate'] = 'Госномер: от 4 до 12 букв и цифр, например А123ВС13.';
    }

    $vehicleFields = ['car_brand' => 'Марка', 'car_model' => 'Модель'];
    foreach ($vehicleFields as $field => $label) {
        if ($values[$field] === '') {
            $errors[$field] = $label . ' автомобиля: обязательное поле.';
        } elseif (!is_valid_vehicle_text($values[$field])) {
            $errors[$field] = $label . ' автомобиля: допустимы буквы, цифры, пробел, дефис и точка (до 50 символов).';
        }
    }

    if ($values['car_year'] !== '') {
        $maxYear = (int) date('Y') + 1;
        if (preg_match('/^\d{4}$/', $values['car_year']) !== 1
            || (int) $values['car_year'] < 1950
            || (int) $values['car_year'] > $maxYear
        ) {
            $errors['car_year'] = 'Год выпуска: от 1950 до ' . $maxYear . ' или оставьте поле пустым.';
        }
    }

    return $errors;
}
