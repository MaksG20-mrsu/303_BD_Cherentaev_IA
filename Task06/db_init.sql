-- Лабораторные работы 6-8. База данных станции технического обслуживания (СТО).
-- Модель из лабораторной работы 6 + таблица master_services (какие услуги выполняет мастер).
-- СУБД: SQLite.
-- Запуск: sqlite3 sto.db ".read db_init.sql"
--
-- Модель:
--   masters              - мастера (кадровый учёт, индивидуальный процент от выручки);
--                          уволенные мастера остаются в базе (dismissal_date), удалять нельзя
--   schedules            - индивидуальный график работы мастера по дням
--   services             - справочник услуг (название, длительность, цена)
--   master_services      - какие услуги может выполнять каждый мастер
--   clients, cars        - клиенты и их автомобили
--   appointments         - предварительные записи к мастеру
--   appointment_services - услуги, выбранные в записи (связь «многие ко многим»)
--   performed_works      - фактически выполненные работы (основа расчёта зарплаты)

-- Проверка внешних ключей в SQLite включается отдельно для каждого соединения.
PRAGMA foreign_keys = ON;

DROP VIEW  IF EXISTS v_master_revenue;
DROP TABLE IF EXISTS performed_works;
DROP TABLE IF EXISTS appointment_services;
DROP TABLE IF EXISTS appointments;
DROP TABLE IF EXISTS master_services;
DROP TABLE IF EXISTS schedules;
DROP TABLE IF EXISTS cars;
DROP TABLE IF EXISTS clients;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS masters;

-- Мастера. Вместо удаления при увольнении заполняется dismissal_date:
-- NULL - работает, иначе - последний рабочий день.
CREATE TABLE masters (
    id             INTEGER PRIMARY KEY,
    last_name      VARCHAR(50)   NOT NULL,
    first_name     VARCHAR(50)   NOT NULL,
    middle_name    VARCHAR(50),
    phone          VARCHAR(20)   NOT NULL UNIQUE,
    hire_date      DATE          NOT NULL CHECK (date(hire_date) IS hire_date),
    dismissal_date DATE          CHECK (dismissal_date IS NULL OR
                                        (date(dismissal_date) IS dismissal_date AND dismissal_date >= hire_date)),
    salary_percent DECIMAL(5, 2) NOT NULL DEFAULT 30
                                 CHECK (salary_percent >= 0 AND salary_percent <= 100)
);

-- Индивидуальный график: одна рабочая смена мастера в конкретный день.
CREATE TABLE schedules (
    master_id  INTEGER    NOT NULL REFERENCES masters (id) ON DELETE RESTRICT,
    work_date  DATE       NOT NULL CHECK (date(work_date) IS work_date),
    start_time VARCHAR(5) NOT NULL CHECK (strftime('%H:%M', start_time) IS start_time),
    end_time   VARCHAR(5) NOT NULL CHECK (strftime('%H:%M', end_time) IS end_time),
    PRIMARY KEY (master_id, work_date),
    CHECK (end_time > start_time)
);

-- Справочник услуг. Услуги, которые больше не оказываются, помечаются is_active = 0
-- (удалить их нельзя, пока на них есть ссылки).
CREATE TABLE services (
    id           INTEGER PRIMARY KEY,
    name         VARCHAR(100)  NOT NULL UNIQUE,
    duration_min INTEGER       NOT NULL CHECK (duration_min > 0),
    price        DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    is_active    INTEGER       NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- Услуги, которые может выполнять мастер (связь «многие ко многим»).
CREATE TABLE master_services (
    master_id  INTEGER NOT NULL REFERENCES masters (id)  ON DELETE RESTRICT,
    service_id INTEGER NOT NULL REFERENCES services (id) ON DELETE RESTRICT,
    PRIMARY KEY (master_id, service_id)
);

CREATE TABLE clients (
    id         INTEGER PRIMARY KEY,
    last_name  VARCHAR(50)  NOT NULL,
    first_name VARCHAR(50)  NOT NULL,
    phone      VARCHAR(20)  NOT NULL UNIQUE,
    email      VARCHAR(100) CHECK (email IS NULL OR email LIKE '%_@_%')
);

CREATE TABLE cars (
    id            INTEGER PRIMARY KEY,
    client_id     INTEGER     NOT NULL REFERENCES clients (id) ON DELETE RESTRICT,
    license_plate VARCHAR(12) NOT NULL UNIQUE,
    brand         VARCHAR(50) NOT NULL,
    model         VARCHAR(50) NOT NULL,
    year          INTEGER     CHECK (year IS NULL OR year BETWEEN 1950 AND 2100)
);

-- Предварительная запись к мастеру. Клиент определяется через автомобиль.
-- Время окончания (end_at) = начало + суммарная длительность выбранных услуг.
-- Статусы: booked - записан, completed - выполнена, cancelled - отменена, no_show - клиент не пришёл.
CREATE TABLE appointments (
    id         INTEGER PRIMARY KEY,
    car_id     INTEGER      NOT NULL REFERENCES cars (id)    ON DELETE RESTRICT,
    master_id  INTEGER      NOT NULL REFERENCES masters (id) ON DELETE RESTRICT,
    start_at   DATETIME     NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', start_at) IS start_at),
    end_at     DATETIME     NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', end_at) IS end_at),
    status     VARCHAR(12)  NOT NULL DEFAULT 'booked'
                            CHECK (status IN ('booked', 'completed', 'cancelled', 'no_show')),
    created_at DATETIME     NOT NULL DEFAULT (datetime('now')),
    comment    VARCHAR(255),
    CHECK (end_at > start_at),
    CHECK (date(end_at) = date(start_at))
);

-- Услуги, выбранные при записи. При удалении записи они удаляются вместе с ней.
CREATE TABLE appointment_services (
    appointment_id INTEGER NOT NULL REFERENCES appointments (id) ON DELETE CASCADE,
    service_id     INTEGER NOT NULL REFERENCES services (id)     ON DELETE RESTRICT,
    PRIMARY KEY (appointment_id, service_id)
);

-- Фактически выполненные работы. master_id - тот, кто реально выполнил работу
-- (может отличаться от записанного, например при замене), price - фактическая
-- стоимость (цена в справочнике со временем меняется).
CREATE TABLE performed_works (
    id             INTEGER PRIMARY KEY,
    appointment_id INTEGER       NOT NULL REFERENCES appointments (id) ON DELETE RESTRICT,
    service_id     INTEGER       NOT NULL REFERENCES services (id)     ON DELETE RESTRICT,
    master_id      INTEGER       NOT NULL REFERENCES masters (id)      ON DELETE RESTRICT,
    performed_at   DATETIME      NOT NULL CHECK (strftime('%Y-%m-%d %H:%M', performed_at) IS performed_at),
    price          DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
    UNIQUE (appointment_id, service_id)
);

-- Индексы для частых запросов (занятость мастера, отчёты, расчёт зарплаты, внешние ключи).
CREATE INDEX idx_masters_last_name            ON masters (last_name);
CREATE INDEX idx_master_services_service      ON master_services (service_id);
CREATE INDEX idx_clients_last_name            ON clients (last_name);
CREATE INDEX idx_cars_client_id               ON cars (client_id);
CREATE INDEX idx_appointments_master_start    ON appointments (master_id, start_at);
CREATE INDEX idx_appointments_car_id          ON appointments (car_id);
CREATE INDEX idx_appointment_services_service ON appointment_services (service_id);
CREATE INDEX idx_performed_works_master_date  ON performed_works (master_id, performed_at);
CREATE INDEX idx_performed_works_service      ON performed_works (service_id);

-- Мастеров удалять нельзя: данные о их работе должны сохраняться.
-- Вместо удаления нужно указать дату увольнения (dismissal_date).
CREATE TRIGGER trg_masters_no_delete
BEFORE DELETE ON masters
BEGIN
    SELECT RAISE(ABORT, 'Мастера нельзя удалять: укажите дату увольнения (dismissal_date)');
END;

-- Контроль записи с учётом занятости мастера (при добавлении записи).
CREATE TRIGGER trg_appointments_check_insert
BEFORE INSERT ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Неверный формат времени записи (нужно ГГГГ-ММ-ДД ЧЧ:ММ)')
    WHERE strftime('%Y-%m-%d %H:%M', NEW.start_at) IS NOT NEW.start_at
       OR strftime('%Y-%m-%d %H:%M', NEW.end_at)   IS NOT NEW.end_at;
    SELECT RAISE(ABORT, 'Мастер не работает в станции на дату записи (не принят или уволен)')
    WHERE NOT EXISTS (SELECT 1 FROM masters m
                      WHERE m.id = NEW.master_id
                        AND m.hire_date <= date(NEW.start_at)
                        AND (m.dismissal_date IS NULL OR m.dismissal_date >= date(NEW.start_at)));
    SELECT RAISE(ABORT, 'Запись выходит за рамки рабочего графика мастера')
    WHERE NOT EXISTS (SELECT 1 FROM schedules s
                      WHERE s.master_id = NEW.master_id
                        AND s.work_date = date(NEW.start_at)
                        AND s.start_time <= strftime('%H:%M', NEW.start_at)
                        AND s.end_time   >= strftime('%H:%M', NEW.end_at));
    SELECT RAISE(ABORT, 'Мастер занят в это время')
    WHERE EXISTS (SELECT 1 FROM appointments a
                  WHERE a.master_id = NEW.master_id
                    AND a.status <> 'cancelled'
                    AND a.start_at < NEW.end_at
                    AND a.end_at   > NEW.start_at);
END;

-- То же при изменении мастера, времени или статуса записи.
CREATE TRIGGER trg_appointments_check_update
BEFORE UPDATE OF master_id, start_at, end_at, status ON appointments
WHEN NEW.status <> 'cancelled'
BEGIN
    SELECT RAISE(ABORT, 'Неверный формат времени записи (нужно ГГГГ-ММ-ДД ЧЧ:ММ)')
    WHERE strftime('%Y-%m-%d %H:%M', NEW.start_at) IS NOT NEW.start_at
       OR strftime('%Y-%m-%d %H:%M', NEW.end_at)   IS NOT NEW.end_at;
    SELECT RAISE(ABORT, 'Мастер не работает в станции на дату записи (не принят или уволен)')
    WHERE NOT EXISTS (SELECT 1 FROM masters m
                      WHERE m.id = NEW.master_id
                        AND m.hire_date <= date(NEW.start_at)
                        AND (m.dismissal_date IS NULL OR m.dismissal_date >= date(NEW.start_at)));
    SELECT RAISE(ABORT, 'Запись выходит за рамки рабочего графика мастера')
    WHERE NOT EXISTS (SELECT 1 FROM schedules s
                      WHERE s.master_id = NEW.master_id
                        AND s.work_date = date(NEW.start_at)
                        AND s.start_time <= strftime('%H:%M', NEW.start_at)
                        AND s.end_time   >= strftime('%H:%M', NEW.end_at));
    SELECT RAISE(ABORT, 'Мастер занят в это время')
    WHERE EXISTS (SELECT 1 FROM appointments a
                  WHERE a.id <> NEW.id
                    AND a.master_id = NEW.master_id
                    AND a.status <> 'cancelled'
                    AND a.start_at < NEW.end_at
                    AND a.end_at   > NEW.start_at);
END;

-- В запись можно включить только услугу, которую выбранный мастер умеет выполнять.
CREATE TRIGGER trg_appointment_services_check
BEFORE INSERT ON appointment_services
BEGIN
    SELECT RAISE(ABORT, 'Выбранный мастер не оказывает эту услугу')
    WHERE NOT EXISTS (SELECT 1 FROM appointments a
                      JOIN master_services ms ON ms.master_id = a.master_id
                      WHERE a.id = NEW.appointment_id AND ms.service_id = NEW.service_id);
END;

-- Представление для расчёта зарплаты: каждая выполненная работа с долей мастера.
-- Зарплата за период = SUM(master_share) по work_date из нужного отрезка.
CREATE VIEW v_master_revenue AS
SELECT m.id AS master_id,
       m.last_name || ' ' || m.first_name || COALESCE(' ' || m.middle_name, '') AS master_name,
       m.salary_percent,
       substr(w.performed_at, 1, 10) AS work_date,
       w.price,
       ROUND(w.price * m.salary_percent / 100.0, 2) AS master_share
FROM performed_works w
JOIN masters m ON m.id = w.master_id;

-- ---------------------------------------------------------------------------
-- Тестовые данные
-- ---------------------------------------------------------------------------

BEGIN TRANSACTION;

-- Мастера (мастер 5 уволен, но его данные остаются в базе)
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (1, 'Иванов', 'Пётр', 'Сергеевич', '+7 927 100-20-01', '2019-03-11', NULL, 40);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (2, 'Смирнова', 'Елена', 'Андреевна', '+7 927 100-20-02', '2021-06-01', NULL, 35);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (3, 'Кузнецов', 'Алексей', 'Викторович', '+7 927 100-20-03', '2022-09-15', NULL, 38.5);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (4, 'Попов', 'Дмитрий', 'Олегович', '+7 927 100-20-04', '2024-02-05', NULL, 30);
INSERT INTO masters (id, last_name, first_name, middle_name, phone, hire_date, dismissal_date, salary_percent) VALUES (5, 'Васильев', 'Игорь', 'Николаевич', '+7 927 100-20-05', '2018-05-20', '2026-09-30', 42);

-- Справочник услуг
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (1, 'Замена масла и масляного фильтра', 40, 1500, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (2, 'Диагностика ходовой части', 30, 800, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (3, 'Компьютерная диагностика двигателя', 45, 1200, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (4, 'Замена тормозных колодок (одна ось)', 60, 2500, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (5, 'Замена воздушного фильтра', 20, 600, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (6, 'Шиномонтаж (4 колеса)', 60, 2000, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (7, 'Балансировка колёс (4 колеса)', 40, 1600, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (8, 'Замена ремня ГРМ', 180, 7500, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (9, 'Замена свечей зажигания', 30, 1000, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (10, 'Регулировка развал-схождения', 60, 2800, 1);
INSERT INTO services (id, name, duration_min, price, is_active) VALUES (11, 'Антикоррозийная обработка кузова', 120, 5000, 0);

-- Какие услуги может выполнять каждый мастер
INSERT INTO master_services (master_id, service_id) VALUES
    (1, 1),
    (1, 2),
    (1, 3),
    (1, 4),
    (1, 5),
    (1, 9),
    (2, 1),
    (2, 2),
    (2, 3),
    (2, 5),
    (2, 6),
    (2, 7),
    (2, 9),
    (2, 10),
    (3, 2),
    (3, 4),
    (3, 6),
    (3, 7),
    (3, 8),
    (3, 10),
    (4, 1),
    (4, 3),
    (4, 5),
    (4, 6),
    (4, 7),
    (4, 9),
    (5, 1),
    (5, 2),
    (5, 4),
    (5, 8),
    (5, 9);

-- Клиенты
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (1, 'Орлов', 'Андрей', '+7 937 200-30-01', 'orlov.a@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (2, 'Фёдорова', 'Мария', '+7 937 200-30-02', 'fedorova.m@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (3, 'Григорьев', 'Сергей', '+7 937 200-30-03', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (4, 'Николаева', 'Ольга', '+7 937 200-30-04', 'nikolaeva.o@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (5, 'Захаров', 'Виктор', '+7 937 200-30-05', NULL);
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (6, 'Макарова', 'Анна', '+7 937 200-30-06', 'makarova.a@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (7, 'Борисов', 'Роман', '+7 937 200-30-07', 'borisov.r@example.com');
INSERT INTO clients (id, last_name, first_name, phone, email) VALUES (8, 'Тихонова', 'Дарья', '+7 937 200-30-08', NULL);

-- Автомобили
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (1, 1, 'А123ВС13', 'Lada', 'Vesta', 2019);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (2, 1, 'К456ОР13', 'Lada', 'Granta', 2016);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (3, 2, 'М789ТХ13', 'Kia', 'Rio', 2020);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (4, 3, 'Н321АЕ13', 'Hyundai', 'Solaris', 2018);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (5, 4, 'О654КМ13', 'Toyota', 'Camry', 2021);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (6, 5, 'Р987НУ13', 'Renault', 'Logan', 2015);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (7, 6, 'С147ХВ13', 'Skoda', 'Octavia', 2017);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (8, 6, 'Т258РА13', 'Volkswagen', 'Polo', 2022);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (9, 7, 'У369ОЕ13', 'Ford', 'Focus', 2014);
INSERT INTO cars (id, client_id, license_plate, brand, model, year) VALUES (10, 8, 'Х741МС13', 'Nissan', 'Qashqai', 2019);

-- Графики работы мастеров (у каждого свой график)
-- мастер 1 (Иванов)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (1, '2026-10-19', '09:00', '18:00'),
    (1, '2026-10-20', '09:00', '18:00'),
    (1, '2026-10-21', '09:00', '18:00'),
    (1, '2026-10-22', '09:00', '18:00'),
    (1, '2026-10-23', '09:00', '18:00'),
    (1, '2026-10-26', '09:00', '18:00'),
    (1, '2026-10-27', '09:00', '18:00'),
    (1, '2026-10-28', '09:00', '18:00'),
    (1, '2026-10-29', '09:00', '18:00'),
    (1, '2026-10-30', '09:00', '18:00'),
    (1, '2026-11-02', '09:00', '18:00'),
    (1, '2026-11-03', '09:00', '18:00'),
    (1, '2026-11-04', '09:00', '18:00'),
    (1, '2026-11-05', '09:00', '18:00'),
    (1, '2026-11-06', '09:00', '18:00'),
    (1, '2026-11-09', '09:00', '18:00'),
    (1, '2026-11-10', '09:00', '18:00'),
    (1, '2026-11-11', '09:00', '18:00'),
    (1, '2026-11-12', '09:00', '18:00'),
    (1, '2026-11-13', '09:00', '18:00'),
    (1, '2026-11-16', '09:00', '18:00'),
    (1, '2026-11-17', '09:00', '18:00'),
    (1, '2026-11-18', '09:00', '18:00'),
    (1, '2026-11-19', '09:00', '18:00'),
    (1, '2026-11-20', '09:00', '18:00'),
    (1, '2026-11-23', '09:00', '18:00'),
    (1, '2026-11-24', '09:00', '18:00'),
    (1, '2026-11-25', '09:00', '18:00'),
    (1, '2026-11-26', '09:00', '18:00'),
    (1, '2026-11-27', '09:00', '18:00'),
    (1, '2026-11-30', '09:00', '18:00'),
    (1, '2026-12-01', '09:00', '18:00'),
    (1, '2026-12-02', '09:00', '18:00'),
    (1, '2026-12-03', '09:00', '18:00'),
    (1, '2026-12-04', '09:00', '18:00'),
    (1, '2026-12-07', '09:00', '18:00'),
    (1, '2026-12-08', '09:00', '18:00'),
    (1, '2026-12-09', '09:00', '18:00'),
    (1, '2026-12-10', '09:00', '18:00'),
    (1, '2026-12-11', '09:00', '18:00'),
    (1, '2026-12-14', '09:00', '18:00'),
    (1, '2026-12-15', '09:00', '18:00'),
    (1, '2026-12-16', '09:00', '18:00'),
    (1, '2026-12-17', '09:00', '18:00'),
    (1, '2026-12-18', '09:00', '18:00'),
    (1, '2026-12-21', '09:00', '18:00'),
    (1, '2026-12-22', '09:00', '18:00'),
    (1, '2026-12-23', '09:00', '18:00'),
    (1, '2026-12-24', '09:00', '18:00'),
    (1, '2026-12-25', '09:00', '18:00'),
    (1, '2026-12-28', '09:00', '18:00'),
    (1, '2026-12-29', '09:00', '18:00'),
    (1, '2026-12-30', '09:00', '18:00'),
    (1, '2026-12-31', '09:00', '18:00'),
    (1, '2027-01-01', '09:00', '18:00'),
    (1, '2027-01-04', '09:00', '18:00'),
    (1, '2027-01-05', '09:00', '18:00'),
    (1, '2027-01-06', '09:00', '18:00'),
    (1, '2027-01-07', '09:00', '18:00'),
    (1, '2027-01-08', '09:00', '18:00'),
    (1, '2027-01-11', '09:00', '18:00'),
    (1, '2027-01-12', '09:00', '18:00'),
    (1, '2027-01-13', '09:00', '18:00'),
    (1, '2027-01-14', '09:00', '18:00'),
    (1, '2027-01-15', '09:00', '18:00'),
    (1, '2027-01-18', '09:00', '18:00'),
    (1, '2027-01-19', '09:00', '18:00'),
    (1, '2027-01-20', '09:00', '18:00'),
    (1, '2027-01-21', '09:00', '18:00'),
    (1, '2027-01-22', '09:00', '18:00'),
    (1, '2027-01-25', '09:00', '18:00'),
    (1, '2027-01-26', '09:00', '18:00'),
    (1, '2027-01-27', '09:00', '18:00'),
    (1, '2027-01-28', '09:00', '18:00'),
    (1, '2027-01-29', '09:00', '18:00');
-- мастер 2 (Смирнова)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (2, '2026-10-20', '10:00', '19:00'),
    (2, '2026-10-21', '10:00', '19:00'),
    (2, '2026-10-22', '10:00', '19:00'),
    (2, '2026-10-23', '10:00', '19:00'),
    (2, '2026-10-24', '10:00', '19:00'),
    (2, '2026-10-27', '10:00', '19:00'),
    (2, '2026-10-28', '10:00', '19:00'),
    (2, '2026-10-29', '10:00', '19:00'),
    (2, '2026-10-30', '10:00', '19:00'),
    (2, '2026-10-31', '10:00', '19:00'),
    (2, '2026-11-03', '10:00', '19:00'),
    (2, '2026-11-04', '10:00', '19:00'),
    (2, '2026-11-05', '10:00', '19:00'),
    (2, '2026-11-06', '10:00', '19:00'),
    (2, '2026-11-07', '10:00', '19:00'),
    (2, '2026-11-10', '10:00', '19:00'),
    (2, '2026-11-11', '10:00', '19:00'),
    (2, '2026-11-12', '10:00', '19:00'),
    (2, '2026-11-13', '10:00', '19:00'),
    (2, '2026-11-17', '10:00', '19:00'),
    (2, '2026-11-18', '10:00', '19:00'),
    (2, '2026-11-19', '10:00', '19:00'),
    (2, '2026-11-20', '10:00', '19:00'),
    (2, '2026-11-21', '10:00', '19:00'),
    (2, '2026-11-24', '10:00', '19:00'),
    (2, '2026-11-25', '10:00', '19:00'),
    (2, '2026-11-26', '10:00', '19:00'),
    (2, '2026-11-27', '10:00', '19:00'),
    (2, '2026-11-28', '10:00', '19:00'),
    (2, '2026-12-01', '10:00', '19:00'),
    (2, '2026-12-02', '10:00', '19:00'),
    (2, '2026-12-03', '10:00', '19:00'),
    (2, '2026-12-04', '10:00', '19:00'),
    (2, '2026-12-05', '10:00', '19:00'),
    (2, '2026-12-08', '10:00', '19:00'),
    (2, '2026-12-09', '10:00', '19:00'),
    (2, '2026-12-10', '10:00', '19:00'),
    (2, '2026-12-11', '10:00', '19:00'),
    (2, '2026-12-12', '10:00', '19:00'),
    (2, '2026-12-15', '10:00', '19:00'),
    (2, '2026-12-16', '10:00', '19:00'),
    (2, '2026-12-17', '10:00', '19:00'),
    (2, '2026-12-18', '10:00', '19:00'),
    (2, '2026-12-19', '10:00', '19:00'),
    (2, '2026-12-22', '10:00', '19:00'),
    (2, '2026-12-23', '10:00', '19:00'),
    (2, '2026-12-24', '10:00', '19:00'),
    (2, '2026-12-25', '10:00', '19:00'),
    (2, '2026-12-26', '10:00', '19:00'),
    (2, '2026-12-29', '10:00', '19:00'),
    (2, '2026-12-30', '10:00', '19:00'),
    (2, '2026-12-31', '10:00', '19:00'),
    (2, '2027-01-01', '10:00', '19:00'),
    (2, '2027-01-02', '10:00', '19:00'),
    (2, '2027-01-05', '10:00', '19:00'),
    (2, '2027-01-06', '10:00', '19:00'),
    (2, '2027-01-07', '10:00', '19:00'),
    (2, '2027-01-08', '10:00', '19:00'),
    (2, '2027-01-09', '10:00', '19:00'),
    (2, '2027-01-12', '10:00', '19:00'),
    (2, '2027-01-13', '10:00', '19:00'),
    (2, '2027-01-14', '10:00', '19:00'),
    (2, '2027-01-15', '10:00', '19:00'),
    (2, '2027-01-16', '10:00', '19:00'),
    (2, '2027-01-19', '10:00', '19:00'),
    (2, '2027-01-20', '10:00', '19:00'),
    (2, '2027-01-21', '10:00', '19:00'),
    (2, '2027-01-22', '10:00', '19:00'),
    (2, '2027-01-23', '10:00', '19:00'),
    (2, '2027-01-26', '10:00', '19:00'),
    (2, '2027-01-27', '10:00', '19:00'),
    (2, '2027-01-28', '10:00', '19:00'),
    (2, '2027-01-29', '10:00', '19:00'),
    (2, '2027-01-30', '10:00', '19:00');
-- мастер 3 (Кузнецов)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (3, '2026-10-19', '08:00', '17:00'),
    (3, '2026-10-20', '08:00', '17:00'),
    (3, '2026-10-22', '08:00', '17:00'),
    (3, '2026-10-23', '08:00', '17:00'),
    (3, '2026-10-26', '08:00', '17:00'),
    (3, '2026-10-27', '08:00', '17:00'),
    (3, '2026-10-29', '08:00', '17:00'),
    (3, '2026-10-30', '08:00', '17:00'),
    (3, '2026-11-02', '08:00', '17:00'),
    (3, '2026-11-03', '08:00', '17:00'),
    (3, '2026-11-05', '08:00', '17:00'),
    (3, '2026-11-06', '08:00', '17:00'),
    (3, '2026-11-09', '08:00', '17:00'),
    (3, '2026-11-10', '08:00', '17:00'),
    (3, '2026-11-12', '08:00', '17:00'),
    (3, '2026-11-13', '08:00', '17:00'),
    (3, '2026-11-16', '08:00', '17:00'),
    (3, '2026-11-17', '08:00', '17:00'),
    (3, '2026-11-19', '08:00', '17:00'),
    (3, '2026-11-20', '08:00', '17:00'),
    (3, '2026-11-23', '08:00', '17:00'),
    (3, '2026-11-24', '08:00', '17:00'),
    (3, '2026-11-26', '08:00', '17:00'),
    (3, '2026-11-27', '08:00', '17:00'),
    (3, '2026-11-30', '08:00', '17:00'),
    (3, '2026-12-01', '08:00', '17:00'),
    (3, '2026-12-03', '08:00', '17:00'),
    (3, '2026-12-04', '08:00', '17:00'),
    (3, '2026-12-07', '08:00', '17:00'),
    (3, '2026-12-08', '08:00', '17:00'),
    (3, '2026-12-10', '08:00', '17:00'),
    (3, '2026-12-11', '08:00', '17:00'),
    (3, '2026-12-14', '08:00', '17:00'),
    (3, '2026-12-15', '08:00', '17:00'),
    (3, '2026-12-17', '08:00', '17:00'),
    (3, '2026-12-18', '08:00', '17:00'),
    (3, '2026-12-21', '08:00', '17:00'),
    (3, '2026-12-22', '08:00', '17:00'),
    (3, '2026-12-24', '08:00', '17:00'),
    (3, '2026-12-25', '08:00', '17:00'),
    (3, '2026-12-28', '08:00', '17:00'),
    (3, '2026-12-29', '08:00', '17:00'),
    (3, '2026-12-31', '08:00', '17:00'),
    (3, '2027-01-01', '08:00', '17:00'),
    (3, '2027-01-04', '08:00', '17:00'),
    (3, '2027-01-05', '08:00', '17:00'),
    (3, '2027-01-07', '08:00', '17:00'),
    (3, '2027-01-08', '08:00', '17:00'),
    (3, '2027-01-11', '08:00', '17:00'),
    (3, '2027-01-12', '08:00', '17:00'),
    (3, '2027-01-14', '08:00', '17:00'),
    (3, '2027-01-15', '08:00', '17:00'),
    (3, '2027-01-18', '08:00', '17:00'),
    (3, '2027-01-19', '08:00', '17:00'),
    (3, '2027-01-21', '08:00', '17:00'),
    (3, '2027-01-22', '08:00', '17:00'),
    (3, '2027-01-25', '08:00', '17:00'),
    (3, '2027-01-26', '08:00', '17:00'),
    (3, '2027-01-28', '08:00', '17:00'),
    (3, '2027-01-29', '08:00', '17:00');
-- мастер 4 (Попов)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (4, '2026-10-19', '09:00', '17:00'),
    (4, '2026-10-21', '09:00', '17:00'),
    (4, '2026-10-23', '09:00', '17:00'),
    (4, '2026-10-24', '10:00', '15:00'),
    (4, '2026-10-26', '09:00', '17:00'),
    (4, '2026-10-28', '09:00', '17:00'),
    (4, '2026-10-30', '09:00', '17:00'),
    (4, '2026-10-31', '10:00', '15:00'),
    (4, '2026-11-02', '09:00', '17:00'),
    (4, '2026-11-04', '09:00', '17:00'),
    (4, '2026-11-06', '09:00', '17:00'),
    (4, '2026-11-07', '10:00', '15:00'),
    (4, '2026-11-09', '09:00', '17:00'),
    (4, '2026-11-11', '09:00', '17:00'),
    (4, '2026-11-13', '09:00', '17:00'),
    (4, '2026-11-16', '09:00', '17:00'),
    (4, '2026-11-18', '09:00', '17:00'),
    (4, '2026-11-20', '09:00', '17:00'),
    (4, '2026-11-21', '10:00', '15:00'),
    (4, '2026-11-23', '09:00', '17:00'),
    (4, '2026-11-25', '09:00', '17:00'),
    (4, '2026-11-27', '09:00', '17:00'),
    (4, '2026-11-28', '10:00', '15:00'),
    (4, '2026-11-30', '09:00', '17:00'),
    (4, '2026-12-02', '09:00', '17:00'),
    (4, '2026-12-04', '09:00', '17:00'),
    (4, '2026-12-05', '10:00', '15:00'),
    (4, '2026-12-07', '09:00', '17:00'),
    (4, '2026-12-09', '09:00', '17:00'),
    (4, '2026-12-11', '09:00', '17:00'),
    (4, '2026-12-12', '10:00', '15:00'),
    (4, '2026-12-14', '09:00', '17:00'),
    (4, '2026-12-16', '09:00', '17:00'),
    (4, '2026-12-18', '09:00', '17:00'),
    (4, '2026-12-19', '10:00', '15:00'),
    (4, '2026-12-21', '09:00', '17:00'),
    (4, '2026-12-23', '09:00', '17:00'),
    (4, '2026-12-25', '09:00', '17:00'),
    (4, '2026-12-26', '10:00', '15:00'),
    (4, '2026-12-28', '09:00', '17:00'),
    (4, '2026-12-30', '09:00', '17:00'),
    (4, '2027-01-01', '09:00', '17:00'),
    (4, '2027-01-02', '10:00', '15:00'),
    (4, '2027-01-04', '09:00', '17:00'),
    (4, '2027-01-06', '09:00', '17:00'),
    (4, '2027-01-08', '09:00', '17:00'),
    (4, '2027-01-09', '10:00', '15:00'),
    (4, '2027-01-11', '09:00', '17:00'),
    (4, '2027-01-13', '09:00', '17:00'),
    (4, '2027-01-15', '09:00', '17:00'),
    (4, '2027-01-16', '10:00', '15:00'),
    (4, '2027-01-18', '09:00', '17:00'),
    (4, '2027-01-20', '09:00', '17:00'),
    (4, '2027-01-22', '09:00', '17:00'),
    (4, '2027-01-23', '10:00', '15:00'),
    (4, '2027-01-25', '09:00', '17:00'),
    (4, '2027-01-27', '09:00', '17:00'),
    (4, '2027-01-29', '09:00', '17:00'),
    (4, '2027-01-30', '10:00', '15:00');
-- мастер 5 (Васильев)
INSERT INTO schedules (master_id, work_date, start_time, end_time) VALUES
    (5, '2026-09-07', '09:00', '18:00'),
    (5, '2026-09-08', '09:00', '18:00'),
    (5, '2026-09-09', '09:00', '18:00'),
    (5, '2026-09-10', '09:00', '18:00'),
    (5, '2026-09-11', '09:00', '18:00'),
    (5, '2026-09-14', '09:00', '18:00'),
    (5, '2026-09-15', '09:00', '18:00'),
    (5, '2026-09-16', '09:00', '18:00'),
    (5, '2026-09-17', '09:00', '18:00'),
    (5, '2026-09-18', '09:00', '18:00'),
    (5, '2026-09-21', '09:00', '18:00'),
    (5, '2026-09-22', '09:00', '18:00'),
    (5, '2026-09-23', '09:00', '18:00'),
    (5, '2026-09-24', '09:00', '18:00'),
    (5, '2026-09-25', '09:00', '18:00'),
    (5, '2026-09-28', '09:00', '18:00'),
    (5, '2026-09-29', '09:00', '18:00'),
    (5, '2026-09-30', '09:00', '18:00');

-- Предварительные записи (триггеры проверяют график и занятость мастера)
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (1, 4, 1, '2026-10-19 10:00', '2026-10-19 11:00', 'cancelled', '2026-10-14 05:15:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (2, 4, 1, '2026-10-19 12:00', '2026-10-19 13:15', 'completed', '2026-10-18 11:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (3, 4, 1, '2026-10-20 09:30', '2026-10-20 10:30', 'completed', '2026-10-17 06:45:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (4, 2, 1, '2026-10-20 10:30', '2026-10-20 11:30', 'completed', '2026-10-17 07:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (5, 8, 1, '2026-10-21 09:30', '2026-10-21 10:30', 'completed', '2026-10-17 04:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (6, 10, 1, '2026-10-21 11:30', '2026-10-21 13:15', 'cancelled', '2026-10-17 07:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (7, 8, 1, '2026-11-05 09:00', '2026-11-05 10:15', 'completed', '2026-10-31 06:15:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (8, 3, 1, '2026-11-13 09:00', '2026-11-13 09:40', 'completed', '2026-11-08 05:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (9, 8, 1, '2026-11-13 10:10', '2026-11-13 10:55', 'completed', '2026-11-09 07:10:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (10, 2, 1, '2026-12-07 09:30', '2026-12-07 10:45', 'booked', '2026-12-01 06:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (11, 1, 1, '2026-12-08 09:00', '2026-12-08 10:15', 'booked', '2026-12-07 08:15:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (12, 9, 1, '2026-12-10 10:00', '2026-12-10 10:40', 'booked', '2026-12-07 04:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (13, 3, 2, '2026-10-27 10:30', '2026-10-27 12:00', 'no_show', '2026-10-21 06:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (14, 9, 2, '2026-11-03 10:30', '2026-11-03 11:40', 'completed', '2026-10-30 10:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (15, 6, 2, '2026-11-03 11:40', '2026-11-03 12:20', 'completed', '2026-11-02 10:55:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (16, 7, 2, '2026-11-11 11:00', '2026-11-11 11:30', 'completed', '2026-11-07 06:45:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (17, 7, 2, '2026-11-11 11:30', '2026-11-11 12:30', 'completed', '2026-11-05 10:30:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (18, 3, 2, '2026-12-01 11:00', '2026-12-01 11:40', 'booked', '2026-11-25 06:45:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (19, 3, 2, '2026-12-01 12:10', '2026-12-01 13:20', 'booked', '2026-11-27 09:25:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (20, 8, 2, '2026-12-04 10:30', '2026-12-04 11:10', 'booked', '2026-11-30 07:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (21, 1, 2, '2026-12-11 10:00', '2026-12-11 10:30', 'booked', '2026-12-10 06:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (22, 10, 3, '2026-10-20 08:30', '2026-10-20 10:00', 'completed', '2026-10-18 08:00:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (23, 3, 3, '2026-10-27 08:00', '2026-10-27 11:00', 'completed', '2026-10-26 05:45:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (24, 6, 3, '2026-10-27 11:00', '2026-10-27 12:30', 'completed', '2026-10-26 08:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (25, 7, 3, '2026-10-29 08:30', '2026-10-29 10:10', 'no_show', '2026-10-28 08:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (26, 6, 3, '2026-10-30 09:00', '2026-10-30 09:40', 'completed', '2026-10-25 04:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (27, 10, 3, '2026-10-30 10:10', '2026-10-30 11:10', 'completed', '2026-10-24 09:40:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (28, 1, 3, '2026-11-02 08:00', '2026-11-02 11:00', 'completed', '2026-10-30 06:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (29, 10, 3, '2026-11-02 12:00', '2026-11-02 12:40', 'cancelled', '2026-10-28 09:45:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (30, 1, 3, '2026-11-05 08:00', '2026-11-05 09:00', 'completed', '2026-11-02 03:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (31, 6, 3, '2026-11-05 10:00', '2026-11-05 11:30', 'completed', '2026-11-01 08:15:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (32, 9, 3, '2026-11-09 09:00', '2026-11-09 10:30', 'completed', '2026-11-06 07:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (33, 6, 3, '2026-11-10 08:30', '2026-11-10 10:10', 'completed', '2026-11-04 04:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (34, 5, 3, '2026-11-10 10:10', '2026-11-10 11:40', 'completed', '2026-11-05 04:40:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (35, 3, 3, '2026-11-13 08:00', '2026-11-13 09:30', 'no_show', '2026-11-09 02:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (36, 9, 3, '2026-12-01 08:30', '2026-12-01 09:30', 'booked', '2026-11-27 03:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (37, 7, 3, '2026-12-04 08:30', '2026-12-04 10:00', 'booked', '2026-12-03 03:15:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (38, 9, 3, '2026-12-10 08:00', '2026-12-10 08:30', 'booked', '2026-12-08 02:30:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (39, 7, 3, '2026-12-10 08:30', '2026-12-10 11:30', 'booked', '2026-12-05 04:15:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (40, 9, 3, '2026-12-11 08:30', '2026-12-11 09:10', 'booked', '2026-12-08 06:30:00', 'Повторное обращение');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (41, 5, 3, '2026-12-11 09:40', '2026-12-11 11:10', 'booked', '2026-12-08 05:10:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (42, 10, 4, '2026-10-21 10:00', '2026-10-21 10:40', 'completed', '2026-10-17 07:45:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (43, 6, 4, '2026-10-21 10:40', '2026-10-21 11:50', 'completed', '2026-10-19 10:40:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (44, 3, 4, '2026-10-24 10:00', '2026-10-24 11:45', 'completed', '2026-10-22 09:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (45, 2, 4, '2026-10-24 12:45', '2026-10-24 13:45', 'completed', '2026-10-19 10:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (46, 8, 4, '2026-10-28 09:00', '2026-10-28 10:40', 'cancelled', '2026-10-25 09:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (47, 5, 4, '2026-10-28 11:40', '2026-10-28 12:40', 'completed', '2026-10-26 10:10:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (48, 7, 4, '2026-10-30 10:00', '2026-10-30 11:15', 'completed', '2026-10-28 06:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (49, 10, 4, '2026-10-30 11:45', '2026-10-30 12:25', 'completed', '2026-10-28 08:30:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (50, 8, 4, '2026-10-31 10:30', '2026-10-31 11:30', 'completed', '2026-10-26 05:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (51, 7, 4, '2026-11-06 10:00', '2026-11-06 11:15', 'completed', '2026-11-01 04:30:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (52, 2, 4, '2026-11-06 12:15', '2026-11-06 13:55', 'completed', '2026-11-02 07:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (53, 1, 4, '2026-11-09 10:00', '2026-11-09 11:10', 'completed', '2026-11-03 07:45:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (54, 8, 4, '2026-11-09 12:10', '2026-11-09 13:25', 'completed', '2026-11-08 11:10:00', 'Нужен подменный автомобиль');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (55, 5, 4, '2026-11-11 09:30', '2026-11-11 11:15', 'completed', '2026-11-08 09:15:00', 'Клиент ожидает в зоне отдыха');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (56, 10, 4, '2026-11-30 09:30', '2026-11-30 10:15', 'booked', '2026-11-24 08:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (57, 3, 4, '2026-12-07 09:30', '2026-12-07 10:10', 'booked', '2026-12-02 04:15:00', 'Просит позвонить за час до приезда');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (58, 8, 5, '2026-09-09 09:00', '2026-09-09 12:00', 'completed', '2026-09-05 06:30:00', 'Просит позвонить за час до приезда');
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (59, 5, 5, '2026-09-09 12:30', '2026-09-09 13:00', 'completed', '2026-09-03 09:00:00', NULL);
INSERT INTO appointments (id, car_id, master_id, start_at, end_at, status, created_at, comment) VALUES (60, 5, 5, '2026-09-30 10:00', '2026-09-30 11:10', 'no_show', '2026-09-25 05:15:00', 'Нужен подменный автомобиль');

-- Услуги в записях
INSERT INTO appointment_services (appointment_id, service_id) VALUES
    (1, 1),
    (1, 5),
    (2, 9),
    (2, 3),
    (3, 4),
    (4, 4),
    (5, 4),
    (6, 1),
    (6, 3),
    (6, 5),
    (7, 9),
    (7, 3),
    (8, 1),
    (9, 3),
    (10, 9),
    (10, 3),
    (11, 9),
    (11, 3),
    (12, 1),
    (13, 10),
    (13, 2),
    (14, 1),
    (14, 9),
    (15, 1),
    (16, 2),
    (17, 10),
    (18, 1),
    (19, 1),
    (19, 9),
    (20, 7),
    (21, 2),
    (22, 10),
    (22, 2),
    (23, 8),
    (24, 10),
    (24, 2),
    (25, 6),
    (25, 7),
    (26, 7),
    (27, 6),
    (28, 8),
    (29, 7),
    (30, 4),
    (31, 4),
    (31, 2),
    (32, 10),
    (32, 2),
    (33, 6),
    (33, 7),
    (34, 10),
    (34, 2),
    (35, 10),
    (35, 2),
    (36, 10),
    (37, 10),
    (37, 2),
    (38, 2),
    (39, 8),
    (40, 7),
    (41, 4),
    (41, 2),
    (42, 1),
    (43, 1),
    (43, 9),
    (44, 1),
    (44, 3),
    (44, 5),
    (45, 1),
    (45, 5),
    (46, 6),
    (46, 7),
    (47, 6),
    (48, 9),
    (48, 3),
    (49, 7),
    (50, 6),
    (51, 9),
    (51, 3),
    (52, 6),
    (52, 7),
    (53, 1),
    (53, 9),
    (54, 9),
    (54, 3),
    (55, 1),
    (55, 3),
    (55, 5),
    (56, 3),
    (57, 1),
    (58, 8),
    (59, 2),
    (60, 1),
    (60, 9);

-- Фактически выполненные работы (цена - фактическая на момент выполнения)
INSERT INTO performed_works (id, appointment_id, service_id, master_id, performed_at, price) VALUES
    (1, 2, 9, 1, '2026-10-19 13:15', 1000),
    (2, 2, 3, 1, '2026-10-19 13:15', 1200),
    (3, 3, 4, 1, '2026-10-20 10:30', 2070.0),
    (4, 4, 4, 1, '2026-10-20 11:30', 2300),
    (5, 5, 4, 1, '2026-10-21 10:30', 2300),
    (6, 7, 9, 1, '2026-11-05 10:15', 1000),
    (7, 7, 3, 1, '2026-11-05 10:15', 1200),
    (8, 8, 1, 1, '2026-11-13 09:40', 1500),
    (9, 9, 3, 1, '2026-11-13 10:55', 1200),
    (10, 14, 1, 2, '2026-11-03 11:40', 1500),
    (11, 14, 9, 2, '2026-11-03 11:40', 1000),
    (12, 15, 1, 2, '2026-11-03 12:20', 1500),
    (13, 16, 2, 1, '2026-11-11 11:30', 800),
    (14, 17, 10, 2, '2026-11-11 12:30', 2800),
    (15, 22, 10, 3, '2026-10-20 10:00', 2600),
    (16, 22, 2, 3, '2026-10-20 10:00', 800),
    (17, 23, 8, 3, '2026-10-27 11:00', 7500),
    (18, 24, 10, 3, '2026-10-27 12:30', 2600),
    (19, 24, 2, 3, '2026-10-27 12:30', 800),
    (20, 26, 7, 3, '2026-10-30 09:40', 1600),
    (21, 27, 6, 3, '2026-10-30 11:10', 2000),
    (22, 28, 8, 3, '2026-11-02 11:00', 7500),
    (23, 30, 4, 3, '2026-11-05 09:00', 2500),
    (24, 31, 4, 3, '2026-11-05 11:30', 2500),
    (25, 31, 2, 3, '2026-11-05 11:30', 800),
    (26, 32, 10, 3, '2026-11-09 10:30', 2800),
    (27, 32, 2, 3, '2026-11-09 10:30', 800),
    (28, 33, 6, 3, '2026-11-10 10:10', 2000),
    (29, 33, 7, 3, '2026-11-10 10:10', 1600),
    (30, 34, 10, 3, '2026-11-10 11:40', 2800),
    (31, 34, 2, 3, '2026-11-10 11:40', 800),
    (32, 42, 1, 4, '2026-10-21 10:40', 1500),
    (33, 43, 1, 4, '2026-10-21 11:50', 1500),
    (34, 43, 9, 4, '2026-10-21 11:50', 1000),
    (35, 44, 1, 4, '2026-10-24 11:45', 1500),
    (36, 44, 3, 4, '2026-10-24 11:45', 1200),
    (37, 44, 5, 4, '2026-10-24 11:45', 600),
    (38, 45, 1, 4, '2026-10-24 13:45', 1500),
    (39, 45, 5, 4, '2026-10-24 13:45', 600),
    (40, 47, 6, 4, '2026-10-28 12:40', 2000),
    (41, 48, 9, 4, '2026-10-30 11:15', 1000),
    (42, 48, 3, 4, '2026-10-30 11:15', 1200),
    (43, 49, 7, 4, '2026-10-30 12:25', 1600),
    (44, 50, 6, 4, '2026-10-31 11:30', 2000),
    (45, 51, 9, 4, '2026-11-06 11:15', 1000),
    (46, 51, 3, 4, '2026-11-06 11:15', 1200),
    (47, 52, 6, 4, '2026-11-06 13:55', 2000),
    (48, 52, 7, 4, '2026-11-06 13:55', 1600),
    (49, 53, 1, 4, '2026-11-09 11:10', 1500),
    (50, 53, 9, 4, '2026-11-09 11:10', 1000),
    (51, 54, 9, 4, '2026-11-09 13:25', 1000),
    (52, 54, 3, 4, '2026-11-09 13:25', 1200),
    (53, 55, 1, 4, '2026-11-11 11:15', 1500),
    (54, 55, 3, 4, '2026-11-11 11:15', 1200),
    (55, 55, 5, 4, '2026-11-11 11:15', 600),
    (56, 58, 8, 5, '2026-09-09 12:00', 7500),
    (57, 59, 2, 5, '2026-09-09 13:00', 800),
    (58, 2, 5, 1, '2026-10-19 13:15', 600);

COMMIT;


-- ---------------------------------------------------------------------------
-- Примеры запросов (не выполняются, приведены для проверки модели)
-- ---------------------------------------------------------------------------
-- Зарплата мастеров за октябрь 2026 г. (процент от выручки у каждого свой):
--   SELECT m.last_name, SUM(w.price) AS revenue,
--          ROUND(SUM(w.price) * m.salary_percent / 100, 2) AS salary
--   FROM masters m JOIN performed_works w ON w.master_id = m.id
--   WHERE w.performed_at >= '2026-10-01' AND w.performed_at < '2026-11-01'
--   GROUP BY m.id ORDER BY m.last_name;
--
-- Работающие и уволенные мастера:
--   SELECT last_name, first_name, CASE WHEN dismissal_date IS NULL THEN 'работает' ELSE 'уволен' END AS state
--   FROM masters ORDER BY dismissal_date IS NOT NULL, last_name;
--
-- Выручка по услугам:
--   SELECT s.name, COUNT(*) AS cnt, SUM(w.price) AS revenue
--   FROM performed_works w JOIN services s ON s.id = w.service_id
--   GROUP BY s.id ORDER BY revenue DESC;
