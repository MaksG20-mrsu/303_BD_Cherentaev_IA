-- ============================================================
-- Лабораторная работа 5. Добавление новых данных
-- Запускать ПОСЛЕ db_init.sql:  sqlite3 movies_rating.db < data_add.sql
-- Запросы не зависят от уже существующих id: связи ищутся подзапросами.
-- ============================================================

PRAGMA foreign_keys = ON;

-- ---------- 1. Пять новых пользователей (я + четыре соседа по списку группы) ----------
-- !!! ЗАМЕНИТЕ имена, e-mail и пол соседей на реальные данные из списка вашей группы !!!
-- Дата регистрации берётся из системного времени: DATE('now').
INSERT INTO users (first_name, last_name, email, gender, register_date, occupation_id) VALUES
    ('Ilya',   'Cherentaev', 'ilya.cherentaev@example.com',  'male',   DATE('now'), (SELECT id FROM occupations WHERE name = 'student')),
    ('Aleksandr',  'Smirnov',   'aleksandr.smirnov@example.com',        'male',   DATE('now'), (SELECT id FROM occupations WHERE name = 'student')),
    ('Maria',  'Ivanova',   'maria.ivanova@example.com',        'female', DATE('now'), (SELECT id FROM occupations WHERE name = 'student')),
    ('Dmitry',  'Kuznetsov',   'dmitry.kuznetsov@example.com',        'male',   DATE('now'), (SELECT id FROM occupations WHERE name = 'student')),
    ('Anna',  'Popova',   'anna.popova@example.com',        'female', DATE('now'), (SELECT id FROM occupations WHERE name = 'student'));

-- ---------- 2. Три новых фильма разных жанров ----------
INSERT INTO movies (title, year) VALUES
    ('Dune: Part Two', 2024),
    ('Inside Out 2',   2024),
    ('Oppenheimer',    2023);

-- Жанры для новых фильмов (id фильмов и жанров находим по названиям)
INSERT INTO movie_genres (movie_id, genre_id)
SELECT m.id, g.id
FROM movies m
JOIN genres g ON g.name IN ('Adventure', 'Sci-Fi')
WHERE m.title = 'Dune: Part Two' AND m.year = 2024;

INSERT INTO movie_genres (movie_id, genre_id)
SELECT m.id, g.id
FROM movies m
JOIN genres g ON g.name IN ('Animation', 'Children', 'Comedy')
WHERE m.title = 'Inside Out 2' AND m.year = 2024;

INSERT INTO movie_genres (movie_id, genre_id)
SELECT m.id, g.id
FROM movies m
JOIN genres g ON g.name IN ('Drama')
WHERE m.title = 'Oppenheimer' AND m.year = 2023;

-- ---------- 3. Три отзыва от меня на добавленные фильмы ----------
-- Пользователь ищется по e-mail, фильм по названию и году, время отзыва - системное.
INSERT INTO ratings (user_id, movie_id, rating, timestamp)
SELECT u.id, m.id, 4.5, CAST(strftime('%s', 'now') AS INTEGER)
FROM users u, movies m
WHERE u.email = 'ilya.cherentaev@example.com'
  AND m.title = 'Dune: Part Two' AND m.year = 2024;

INSERT INTO ratings (user_id, movie_id, rating, timestamp)
SELECT u.id, m.id, 4.0, CAST(strftime('%s', 'now') AS INTEGER)
FROM users u, movies m
WHERE u.email = 'ilya.cherentaev@example.com'
  AND m.title = 'Inside Out 2' AND m.year = 2024;

INSERT INTO ratings (user_id, movie_id, rating, timestamp)
SELECT u.id, m.id, 5.0, CAST(strftime('%s', 'now') AS INTEGER)
FROM users u, movies m
WHERE u.email = 'ilya.cherentaev@example.com'
  AND m.title = 'Oppenheimer' AND m.year = 2023;
