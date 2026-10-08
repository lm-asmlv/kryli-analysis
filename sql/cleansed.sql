-- ============================================================
-- CLEANSED LAYER for @krylikryli
-- Создаёт cleansed_posts из raw_posts: метрики, ER, нормировка,
-- бакеты длины, время между постами, флаги (personal, recent,
-- holiday, pinned, forwarded).
-- Самодостаточный: is_holiday считается здесь же, отдельный
-- holidays.sql больше не нужен.
-- ============================================================

SET client_encoding = 'UTF8';

DROP TABLE IF EXISTS cleansed_posts;

WITH base AS (
    SELECT
        post_id,
        date_time,
        text,
        views,
        reactions_total,
        reactions_breakdown,
        forwards,
        replies,
        is_pinned,
        is_forwarded,
        hashtags,
        media_type,
        COALESCE(LENGTH(text), 0)                        AS text_length,
        EXTRACT(HOUR FROM date_time)                     AS hour,
        EXTRACT(DOW  FROM date_time)                     AS weekday,
        (date_time > NOW() - INTERVAL '7 days')          AS is_recent,
        -- is_holiday: праздничные дни (месяц-день фиксированы)
        (
            (EXTRACT(MONTH FROM date_time), EXTRACT(DAY FROM date_time)) IN (
                (1,1),(1,2),(1,3),(1,4),(1,5),(1,6),(1,7),(1,8),   -- Новый год
                (2,23),                                            -- 23 февраля
                (3,8),                                             -- 8 марта
                (5,1),                                             -- 1 мая
                (5,9),                                             -- 9 мая
                (6,12),                                            -- 12 июня
                (11,4),                                            -- 4 ноября
                (12,31)                                            -- 31 декабря
            )
        )                                                AS is_holiday
    FROM raw_posts
),
with_metrics AS (
    SELECT
        b.*,
        ROUND(reactions_total::numeric / NULLIF(views, 0), 6) AS reactions_per_view,
        ROUND(replies::numeric        / NULLIF(views, 0), 6) AS replies_per_view,
        ROUND(forwards::numeric       / NULLIF(views, 0), 6) AS forwards_per_view,
        ROUND((reactions_total + replies + forwards)::numeric / NULLIF(views, 0), 6) AS er,
        ROUND(
            EXTRACT(EPOCH FROM (date_time - LAG(date_time) OVER (ORDER BY date_time))) / 3600.0
        ::numeric, 2) AS time_since_prev_post,
        (text ILIKE '%я %' OR text ILIKE 'я %' OR text ILIKE '% мне %'
         OR text ILIKE '% мой %' OR text ILIKE '% моя %' OR text ILIKE '% мои %'
         OR text ILIKE '% меня %')                       AS is_personal_heur
    FROM base b
),
channel_median AS (
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY er) AS er_median
    FROM with_metrics
    WHERE er IS NOT NULL
),
with_norm AS (
    SELECT
        m.*,
        ROUND( (m.er::numeric / NULLIF(cm.er_median::numeric, 0))::numeric, 4) AS er_norm,
        ntile(3) OVER (ORDER BY m.text_length) AS length_tertile
    FROM with_metrics m
    CROSS JOIN channel_median cm
)
SELECT
    *,
    CASE length_tertile
        WHEN 1 THEN 'short'
        WHEN 2 THEN 'medium'
        WHEN 3 THEN 'long'
    END AS length_bucket
INTO cleansed_posts
FROM with_norm;