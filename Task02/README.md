# Лабораторная работа 2. Подготовка скриптов для создания таблиц и добавления данных (ETL в SQLite)

## Описание

Утилита `make_db_init.py` читает исходные текстовые файлы с данными (`movies.csv`, `ratings.csv`, `tags.csv`, `users.txt`) и генерирует SQL-скрипт `db_init.sql`. Скрипт удаляет старые таблицы, создаёт новые (`CREATE TABLE`) и загружает в них данные (`INSERT INTO`).

Скрипт `db_init.bat` запускает утилиту и загружает полученный SQL-скрипт в базу данных `movies_rating.db` с помощью `sqlite3`.

## Требования к окружению

| Компонент | Версия | Проверка |
|---|---|---|
| Python | 3.x (проверено на 3.12.3) | `python3 --version` |
| SQLite (утилита `sqlite3`) | 3.x (проверено на 3.45.1) | `sqlite3 --version` |
| Git | любая актуальная (проверено на 2.43.0) | `git --version` |
| Bash | Linux/macOS: встроен. Windows: Git Bash или WSL | |

Дополнительно:

- `python3` и `sqlite3` должны быть доступны в переменной окружения `PATH`.
- Внешние Python-библиотеки не нужны, используются только модули стандартной библиотеки (`csv`, `os`, `re`).
- Установка `sqlite3` в Ubuntu/Debian: `sudo apt install sqlite3`.

## Запуск

Из каталога `Task02`:

```bash
./db_init.bat
```

Если файл не запускается из-за прав доступа, выполните `chmod +x db_init.bat`.

Что делает `db_init.bat`:

1. `python3 make_db_init.py` генерирует файл `db_init.sql`.
2. `sqlite3 movies_rating.db < db_init.sql` выполняет скрипт и создаёт заполненную базу `movies_rating.db`.

Повторный запуск безопасен: существующие таблицы удаляются и создаются заново, данные не дублируются.

## Структура базы данных

**movies**: `id` (PK), `title` VARCHAR(160), `year` INTEGER, `genres` VARCHAR(80).
Год выделяется из названия (`Toy Story (1995)` → `Toy Story`, `1995`). Если года нет, записывается `NULL`.

**ratings**: `id` (PK), `user_id`, `movie_id`, `rating` REAL, `timestamp` INTEGER.

**tags**: `id` (PK), `user_id`, `movie_id`, `tag` VARCHAR(90), `timestamp` INTEGER.

**users**: `id` (PK), `name` VARCHAR(30), `email` VARCHAR(40), `gender` VARCHAR(6), `register_date` DATE, `occupation` VARCHAR(20).

Размеры текстовых полей подобраны по максимальной длине значений в исходных файлах.

## Проверка результата

```bash
sqlite3 movies_rating.db "SELECT COUNT(*) FROM movies; SELECT COUNT(*) FROM ratings; SELECT COUNT(*) FROM tags; SELECT COUNT(*) FROM users;"
```

Ожидаемое количество записей:

| Таблица | Записей |
|---|---|
| movies | 9742 |
| ratings | 18773 |
| tags | 3683 |
| users | 943 |

## Состав каталога

| Файл | Назначение |
|---|---|
| `make_db_init.py` | генератор SQL-скрипта `db_init.sql` |
| `db_init.bat` | запуск генерации и загрузки в БД (shell-скрипт, режим `+x`) |
| `movies.csv`, `ratings.csv`, `tags.csv`, `users.txt` | исходные данные |
| `README.md` | описание работы |

Файлы `db_init.sql` и `movies_rating.db` генерируются при запуске