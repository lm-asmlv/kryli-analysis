CREATE TABLE IF NOT EXISTS raw_posts (
    post_id             BIGINT PRIMARY KEY,
    date_time           TIMESTAMPTZ NOT NULL,
    text                TEXT,
    views               INTEGER DEFAULT 0,
    reactions_total     INTEGER DEFAULT 0,
    reactions_breakdown JSONB,
    forwards            INTEGER DEFAULT 0,
    replies             INTEGER DEFAULT 0,
    is_pinned           BOOLEAN DEFAULT FALSE,
    is_forwarded        BOOLEAN DEFAULT FALSE,
    hashtags            TEXT[],
    media_type          TEXT,
    loaded_at           TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_posts_date_time ON raw_posts (date_time);