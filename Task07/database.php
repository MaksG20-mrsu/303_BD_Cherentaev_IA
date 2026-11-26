<?php

declare(strict_types=1);

/**
 * Доступ к базе данных станции технического обслуживания (лабораторная работа 6).
 * Используется и консольным сценарием task7_cli.php, и веб-страницей index.php.
 */

const DATABASE_PATH = __DIR__ . '/sto.db';
const INIT_SCRIPT_PATH = __DIR__ . '/db_init.sql';

/**
 * Открывает базу данных SQLite через PDO.
 * Если файла базы ещё нет, он создаётся и заполняется командами из db_init.sql.
 */
function open_database(): PDO
{
    $isNewDatabase = !file_exists(DATABASE_PATH);

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

/**
 * Возвращает всех мастеров (в том числе уволенных): номер, ФИО и признак увольнения.
 *
 * @return array<int, array{id: int|string, full_name: string, is_dismissed: int|string}>
 */
function find_all_masters(PDO $pdo): array
{
    $statement = $pdo->prepare(
        "SELECT id,
                last_name || ' ' || first_name || COALESCE(' ' || middle_name, '') AS full_name,
                dismissal_date IS NOT NULL AS is_dismissed
         FROM masters
         ORDER BY id"
    );
    $statement->execute();

    return $statement->fetchAll();
}

/**
 * Возвращает список фактически выполненных работ, отсортированный по фамилии мастера
 * и дате выполнения. Если указан $masterId, выбираются работы только этого мастера.
 *
 * @return array<int, array{master_id: int|string, master_full_name: string, work_date: string, service_name: string, price: int|float|string}>
 */
function find_performed_works(PDO $pdo, ?int $masterId = null): array
{
    $sql = "SELECT m.id AS master_id,
                   m.last_name || ' ' || m.first_name || COALESCE(' ' || m.middle_name, '') AS master_full_name,
                   substr(w.performed_at, 1, 10) AS work_date,
                   s.name AS service_name,
                   w.price AS price
            FROM performed_works AS w
            JOIN masters AS m ON m.id = w.master_id
            JOIN services AS s ON s.id = w.service_id";

    if ($masterId !== null) {
        $sql .= ' WHERE m.id = :master_id';
    }

    $sql .= ' ORDER BY m.last_name, m.id, w.performed_at, w.id';

    $statement = $pdo->prepare($sql);
    if ($masterId !== null) {
        $statement->bindValue(':master_id', $masterId, PDO::PARAM_INT);
    }
    $statement->execute();

    return $statement->fetchAll();
}
