import csv
import os
import re

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_FILE = os.path.join(BASE_DIR, "db_init.sql")


def path(name):
    return os.path.join(BASE_DIR, name)


def q(value):
   
    if value is None or value == "":
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def num(value):
    
    return "NULL" if value is None or value == "" else str(value)


def split_title_year(raw_title):
    
    m = re.match(r"^(.*?)\s*\((\d{4})\)\s*$", raw_title)
    if m:
        return m.group(1), int(m.group(2))
    return raw_title.strip(), None


SCHEMA = """
DROP TABLE IF EXISTS movies;
DROP TABLE IF EXISTS ratings;
DROP TABLE IF EXISTS tags;
DROP TABLE IF EXISTS users;

CREATE TABLE movies (
    id     INTEGER PRIMARY KEY,
    title  VARCHAR(160) NOT NULL,
    year   INTEGER,
    genres VARCHAR(80)
);

CREATE TABLE ratings (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id   INTEGER NOT NULL,
    movie_id  INTEGER NOT NULL,
    rating    REAL NOT NULL,
    timestamp INTEGER NOT NULL
);

CREATE TABLE tags (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id   INTEGER NOT NULL,
    movie_id  INTEGER NOT NULL,
    tag       VARCHAR(90) NOT NULL,
    timestamp INTEGER NOT NULL
);

CREATE TABLE users (
    id            INTEGER PRIMARY KEY,
    name          VARCHAR(30) NOT NULL,
    email         VARCHAR(40),
    gender        VARCHAR(6),
    register_date DATE,
    occupation    VARCHAR(20)
);
"""


def main():
    with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as out:
        out.write(SCHEMA)
        out.write("\nBEGIN TRANSACTION;\n")

      
        with open(path("movies.csv"), encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                title, year = split_title_year(r["title"])
                out.write(
                    "INSERT INTO movies (id, title, year, genres) VALUES "
                    f"({num(r['movieId'])}, {q(title)}, {num(year)}, {q(r['genres'])});\n"
                )

        
        with open(path("ratings.csv"), encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                out.write(
                    "INSERT INTO ratings (user_id, movie_id, rating, timestamp) VALUES "
                    f"({num(r['userId'])}, {num(r['movieId'])}, {num(r['rating'])}, {num(r['timestamp'])});\n"
                )

        
        with open(path("tags.csv"), encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                out.write(
                    "INSERT INTO tags (user_id, movie_id, tag, timestamp) VALUES "
                    f"({num(r['userId'])}, {num(r['movieId'])}, {q(r['tag'])}, {num(r['timestamp'])});\n"
                )

        
        with open(path("users.txt"), encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\r\n")
                if not line:
                    continue
                p = line.split("|")
                out.write(
                    "INSERT INTO users (id, name, email, gender, register_date, occupation) VALUES "
                    f"({num(p[0])}, {q(p[1])}, {q(p[2])}, {q(p[3])}, {q(p[4])}, {q(p[5])});\n"
                )

        out.write("COMMIT;\n")

    print("Создан файл:", OUT_FILE)


if __name__ == "__main__":
    main()