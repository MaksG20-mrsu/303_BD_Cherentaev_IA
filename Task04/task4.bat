#!/bin/bash
chcp 65001

sqlite3 movies_rating.db < db_init.sql

echo "1. Найти все пары пользователей, оценивших один и тот же фильм (первые 100 записей)."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
SELECT u1.name AS user1, u2.name AS user2, m.title AS movie
FROM ratings r1
JOIN ratings r2 ON r1.movie_id = r2.movie_id AND r1.user_id < r2.user_id
JOIN users u1 ON u1.id = r1.user_id
JOIN users u2 ON u2.id = r2.user_id
JOIN movies m ON m.id = r1.movie_id
LIMIT 100;"
echo " "

echo "2. Найти 10 самых свежих оценок от разных пользователей."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH last_ratings AS (
    SELECT r.*, ROW_NUMBER() OVER (PARTITION BY r.user_id ORDER BY r.timestamp DESC) AS rn
    FROM ratings r
)
SELECT m.title AS movie, u.name AS user, l.rating,
       date(l.timestamp, 'unixepoch') AS rating_date
FROM last_ratings l
JOIN movies m ON m.id = l.movie_id
JOIN users u ON u.id = l.user_id
WHERE l.rn = 1
ORDER BY l.timestamp DESC
LIMIT 10;"
echo " "

echo "3. Фильмы с максимальным и минимальным средним рейтингом, колонка Рекомендуем."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH avg_r AS (
    SELECT movie_id, AVG(rating) AS avg_rating
    FROM ratings
    GROUP BY movie_id
)
SELECT m.title, m.year, ROUND(a.avg_rating, 2) AS avg_rating,
       CASE WHEN a.avg_rating = (SELECT MAX(avg_rating) FROM avg_r)
            THEN 'Да' ELSE 'Нет' END AS 'Рекомендуем'
FROM avg_r a
JOIN movies m ON m.id = a.movie_id
WHERE a.avg_rating = (SELECT MAX(avg_rating) FROM avg_r)
   OR a.avg_rating = (SELECT MIN(avg_rating) FROM avg_r)
ORDER BY m.year, m.title;"
echo " "

echo "4. Количество оценок и средняя оценка от пользователей-женщин за 2010-2012 годы."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
SELECT COUNT(*) AS ratings_count, ROUND(AVG(r.rating), 2) AS avg_rating
FROM ratings r
JOIN users u ON u.id = r.user_id
WHERE u.gender = 'female'
  AND CAST(strftime('%Y', r.timestamp, 'unixepoch') AS INTEGER) BETWEEN 2010 AND 2012;"
echo " "

echo "5. Фильмы со средней оценкой и местом в рейтинге (первые 20 записей)."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
SELECT m.title, m.year, ROUND(AVG(r.rating), 2) AS avg_rating,
       RANK() OVER (ORDER BY AVG(r.rating) DESC) AS rating_place
FROM movies m
JOIN ratings r ON r.movie_id = m.id
GROUP BY m.id
ORDER BY m.year, m.title
LIMIT 20;"
echo " "

echo "6. 10 последних зарегистрированных пользователей в формате Фамилия Имя|Дата регистрации."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
SELECT substr(name, instr(name, ' ') + 1) || ' ' || substr(name, 1, instr(name, ' ') - 1)
       || '|' || register_date AS user_info
FROM users
ORDER BY register_date DESC
LIMIT 10;"
echo " "

echo "7. Таблица умножения от 1 до 10 с помощью рекурсивного CTE."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH RECURSIVE n(i) AS (
    SELECT 1
    UNION ALL
    SELECT i + 1 FROM n WHERE i < 10
)
SELECT a.i || 'x' || b.i || '=' || (a.i * b.i) AS multiplication
FROM n a, n b
ORDER BY a.i, b.i;"
echo " "

echo "8. Все жанры из таблицы movies с помощью рекурсивного CTE."
echo --------------------------------------------------
sqlite3 movies_rating.db -box -echo "
WITH RECURSIVE split(genre, rest) AS (
    SELECT '', genres || '|' FROM movies
    UNION ALL
    SELECT substr(rest, 1, instr(rest, '|') - 1),
           substr(rest, instr(rest, '|') + 1)
    FROM split
    WHERE rest <> ''
)
SELECT DISTINCT genre
FROM split
WHERE genre <> ''
ORDER BY genre;"
