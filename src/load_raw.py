import json
import os
from datetime import datetime

import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

load_dotenv()

DB = dict(
    host=os.getenv("PG_HOST", "localhost"),
    port=os.getenv("PG_PORT", "5432"),
    dbname=os.getenv("PG_DB", "kryli"),
    user=os.getenv("PG_USER", "kryli"),
    password=os.getenv("PG_PASSWORD", "kryli_pass"),
)

def parse_dt(s):
    return datetime.fromisoformat(s)

def main():
    posts = json.load(open("data/raw_posts.json", encoding="utf-8"))

    rows = [(
        p["post_id"],
        parse_dt(p["date_time"]),
        p["text"],
        p["views"],
        p["reactions_total"],
        json.dumps(p["reactions_breakdown"]),   # JSONB
        p["forwards"],
        p["replies"],
        p["is_pinned"],
        p["is_forwarded"],
        p["hashtags"],                          # TEXT[]
        p["media_type"],
    ) for p in posts]

    conn = psycopg2.connect(**DB)
    cur = conn.cursor()

    # upsert по post_id: INSERT ... ON CONFLICT DO UPDATE
    sql = """
    INSERT INTO raw_posts (
        post_id, date_time, text, views, reactions_total,
        reactions_breakdown, forwards, replies, is_pinned,
        is_forwarded, hashtags, media_type
    ) VALUES %s
    ON CONFLICT (post_id) DO UPDATE SET
        date_time = EXCLUDED.date_time,
        text = EXCLUDED.text,
        views = EXCLUDED.views,
        reactions_total = EXCLUDED.reactions_total,
        reactions_breakdown = EXCLUDED.reactions_breakdown,
        forwards = EXCLUDED.forwards,
        replies = EXCLUDED.replies,
        is_pinned = EXCLUDED.is_pinned,
        is_forwarded = EXCLUDED.is_forwarded,
        hashtags = EXCLUDED.hashtags,
        media_type = EXCLUDED.media_type,
        loaded_at = NOW();
    """
    execute_values(cur, sql, rows)
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM raw_posts;")
    total = cur.fetchone()[0]
    print(f"Загружено строк в raw_posts: {total}")

    cur.close()
    conn.close()

if __name__ == "__main__":
    main()