"""
ETL: идемпотентная загрузка постов Telegram-канала @krylikryli в PostgreSQL.

Закрывает чек-лист п. 9 (наличие etl/load_telegram.py).

Как работает:
  1. Читает data/raw_posts.json (результат extract.py через Telethon).
  2. Делает UPSERT в raw_posts по post_id:
        - новые посты     → INSERT;
        - существующие    → UPDATE (обновляем метрики: views, reactions,
                            forwards, replies — они растут со временем).
  3. Инкрементальная логика:
        - берём только новые + «свежие» (обновлённые за последние 14 дней),
          чтобы не перезаписывать всю историю каждый запуск.

Идемпотентность: повторный запуск на том же JSON не меняет данные.

Запуск:
    python -m etl.load_telegram
или
    python etl/load_telegram.py
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

load_dotenv()

ROOT = Path(__file__).resolve().parent.parent
RAW_PATH = ROOT / "data" / "raw_posts.json"

DB = dict(
    host=os.getenv("PG_HOST", "127.0.0.1"),
    port=os.getenv("PG_PORT", "5432"),
    dbname=os.getenv("PG_DB", "kryli"),
    user=os.getenv("PG_USER", "kryli"),
    password=os.getenv("PG_PASSWORD", "kryli_pass"),
)

# Посты «моложе» этого окна будем обновлять повторно,
# т.к. их метрики (просмотры/реакции) ещё растут.
REFRESH_WINDOW_DAYS = 14


def parse_dt(s: str) -> datetime:
    return datetime.fromisoformat(s)


def load_json(path: Path) -> list[dict]:
    if not path.exists():
        raise FileNotFoundError(f"Нет файла с данными: {path}")
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def build_rows(posts: list[dict]) -> list[tuple]:
    """Преобразовать список постов в кортежи для UPSERT."""
    rows = []
    for p in posts:
        rows.append((
            p["post_id"],
            parse_dt(p["date_time"]),
            p["text"],
            p["views"],
            p["reactions_total"],
            json.dumps(p["reactions_breakdown"]),  # JSONB
            p["forwards"],
            p["replies"],
            p["is_pinned"],
            p["is_forwarded"],
            p["hashtags"],                          # TEXT[]
            p["media_type"],
        ))
    return rows


UPSERT_SQL = """
INSERT INTO raw_posts (
    post_id, date_time, text, views, reactions_total,
    reactions_breakdown, forwards, replies, is_pinned,
    is_forwarded, hashtags, media_type
) VALUES %s
ON CONFLICT (post_id) DO UPDATE SET
    date_time           = EXCLUDED.date_time,
    text                = EXCLUDED.text,
    views               = EXCLUDED.views,
    reactions_total     = EXCLUDED.reactions_total,
    reactions_breakdown = EXCLUDED.reactions_breakdown,
    forwards            = EXCLUDED.forwards,
    replies             = EXCLUDED.replies,
    is_pinned           = EXCLUDED.is_pinned,
    is_forwarded        = EXCLUDED.is_forwarded,
    hashtags            = EXCLUDED.hashtags,
    media_type          = EXCLUDED.media_type,
    loaded_at           = NOW();
"""


def main() -> int:
    print(f"→ Источник: {RAW_PATH}")
    posts = load_json(RAW_PATH)
    print(f"  постов в дампе: {len(posts)}")

    conn = psycopg2.connect(**DB)
    conn.autocommit = False
    cur = conn.cursor()

    # --- 1. Какие посты уже есть в базе ------------------------
    ids = [p["post_id"] for p in posts]
    cur.execute("SELECT post_id FROM raw_posts WHERE post_id = ANY(%s);", (ids,))
    existing = {r[0] for r in cur.fetchall()}

    # --- 2. Отбираем на загрузку: новые + «свежие» -------------
    # (в дампе уже всё есть, но при инкременте из Telethon —
    #  обновляем только новые и недавние)
    cutoff = datetime.now(timezone.utc) - timedelta(days=REFRESH_WINDOW_DAYS)

    def needs_update(p: dict) -> bool:
        if p["post_id"] not in existing:
            return True
        dt = parse_dt(p["date_time"])
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt > cutoff

    to_load = [p for p in posts if needs_update(p)]
    skipped = len(posts) - len(to_load)
    print(f"  к загрузке: {len(to_load)} (новых + свежих), пропущено: {skipped}")

    if to_load:
        rows = build_rows(to_load)
        execute_values(cur, UPSERT_SQL, rows)
        conn.commit()
        print(f"✓ UPSERT выполнен: {len(rows)} строк")
    else:
        print("⏭  нечего обновлять")

    # --- 3. Контроль -------------------------------------------
    cur.execute("SELECT COUNT(*), MAX(loaded_at) FROM raw_posts;")
    total, last = cur.fetchone()
    print(f"— raw_posts: {total} строк, последняя загрузка: {last}")

    cur.close()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
