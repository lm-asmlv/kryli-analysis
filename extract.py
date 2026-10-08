import os
import json
from datetime import datetime, timedelta, timezone

from dotenv import load_dotenv
from telethon.sync import TelegramClient
from telethon.tl.types import MessageMediaPhoto, MessageMediaDocument

load_dotenv()

API_ID = int(os.getenv("API_ID"))
API_HASH = os.getenv("API_HASH")
CHANNEL = os.getenv("CHANNEL", "krylikryli")
WINDOW_MONTHS = int(os.getenv("WINDOW_MONTHS", "12"))

OUTPUT = "data/raw_posts.json"
SESSION = "kryli_session"   # появится файл сессии после логина

# граница окна: 12 месяцев назад
date_from = datetime.now(timezone.utc) - timedelta(days=30 * WINDOW_MONTHS)


def media_type(msg):
    if msg.photo:
        return "photo"
    if isinstance(msg.media, MessageMediaDocument):
        return "document"
    return "none"


def reactions_dict(msg):
    result = {}
    if msg.reactions and msg.reactions.results:
        for r in msg.reactions.results:
            key = getattr(r.reaction, "emoticon", None) or str(type(r.reaction).__name__)
            result[key] = r.count
    return result


def hashtags(text):
    if not text:
        return []
    return [w for w in text.split() if w.startswith("#")]


def main():
    os.makedirs("data", exist_ok=True)
    posts = []

    with TelegramClient(
        SESSION, API_ID, API_HASH,
        lang_code="ru",
        system_lang_code="ru-RU"
    ) as client:
        # iter_messages идёт от новых к старым; offset_date = date_from не даёт уйти раньше окна
        for msg in client.iter_messages(CHANNEL, offset_date=datetime.now(timezone.utc)):
            if msg.date < date_from:
                break  # дошли до границы 12 месяцев — стоп
            if not msg.id:
                continue

            rb = reactions_dict(msg)
            posts.append({
                "post_id": msg.id,
                "date_time": msg.date.isoformat(),
                "text": msg.message or "",
                "views": msg.views or 0,
                "reactions_total": sum(rb.values()),
                "reactions_breakdown": rb,
                "forwards": msg.forwards or 0,
                "replies": msg.replies.replies if msg.replies else 0,
                "is_pinned": bool(msg.pinned),
                "is_forwarded": msg.fwd_from is not None,
                "hashtags": hashtags(msg.message),
                "media_type": media_type(msg),
            })

    with open(OUTPUT, "w", encoding="utf-8") as f:
        json.dump(posts, f, ensure_ascii=False, indent=2)

    print(f"Готово: {len(posts)} постов сохранено в {OUTPUT}")


if __name__ == "__main__":
    main()
