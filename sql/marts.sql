-- MARTS: агрегированные витрины для анализа канала @krylikryli
-- Весь SQL для всех витрин в одном файле.
-- Источник: cleansed_posts. Только посты старше 7 дней (NOT is_recent).
-- Каждая витрина содержит count(*) + avg_* + er + er_norm.
-- ============================================================

SET client_encoding = 'UTF8';

-- ------------------------------------------------------------
-- 1. mart_by_hour — вовлечённость по часу публикации
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_hour;
CREATE TABLE mart_by_hour AS
SELECT
    hour,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY hour
ORDER BY hour;

-- ------------------------------------------------------------
-- 2. mart_by_weekday — вовлечённость по дню недели
--    weekday: 0=Вс, 1=Пн, ... 6=Сб (EXTRACT(DOW))
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_weekday;
CREATE TABLE mart_by_weekday AS
SELECT
    weekday,
    CASE weekday
        WHEN 0 THEN 'Sun' WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue'
        WHEN 3 THEN 'Wed' WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri'
        WHEN 6 THEN 'Sat'
    END AS weekday_name,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY weekday
ORDER BY weekday;

-- ------------------------------------------------------------
-- 3. mart_by_content_type — по типу медиа
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_content_type;
CREATE TABLE mart_by_content_type AS
SELECT
    COALESCE(media_type, 'none')                        AS media_type,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY COALESCE(media_type, 'none')
ORDER BY posts_count DESC;

-- ------------------------------------------------------------
-- 4. mart_by_text_flags — по текстовым/статусным флагам
--    Для каждого флага: сколько постов, средний ER и т.д.
--    Реализовано через UNION по каждому флагу (unpivot).
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_text_flags;
CREATE TABLE mart_by_text_flags AS
WITH flagged AS (
    SELECT 'is_personal_heur' AS flag, is_personal_heur AS value, views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_pinned',   is_pinned,   views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_forwarded',is_forwarded,views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_holiday',  is_holiday,  views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
)
SELECT
    flag,
    value,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM flagged
GROUP BY flag, value
ORDER BY flag, value;

-- ------------------------------------------------------------
-- 5. mart_by_interval — по промежутку между постами
--    Бакеты: <6ч, 6-24ч, 24-72ч, >72ч
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_interval;
CREATE TABLE mart_by_interval AS
SELECT
    CASE
        WHEN time_since_prev_post IS NULL      THEN 'first_post'
        WHEN time_since_prev_post < 6          THEN 'lt_6h'
        WHEN time_since_prev_post < 24         THEN '6_24h'
        WHEN time_since_prev_post < 72         THEN '24_72h'
        ELSE 'gt_72h'
    END                                                 AS interval_bucket,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY interval_bucket
ORDER BY posts_count DESC;

-- ------------------------------------------------------------
-- 6. mart_by_text_length — по длине текста (терцили)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_text_length;
CREATE TABLE mart_by_text_length AS
SELECT
    length_bucket,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(text_length)::numeric, 1)                 AS avg_text_length,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY length_bucket
ORDER BY avg_text_length;

-- ------------------------------------------------------------
-- 7. mart_by_combination — пересечение факторов
--    Самое интересное: personal+вечер, promo+утро и т.д.
--    Используем 2 ключевых фактора: тип текста × часть дня
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_combination;
CREATE TABLE mart_by_combination AS
SELECT
    CASE WHEN is_personal_heur THEN 'personal' ELSE 'promo' END AS content_kind,
    CASE
        WHEN hour BETWEEN 0  AND 5  THEN 'night'
        WHEN hour BETWEEN 6  AND 11 THEN 'morning'
        WHEN hour BETWEEN 12 AND 17 THEN 'day'
        ELSE 'evening'
    END                                                 AS part_of_day,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS er_norm
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY content_kind, part_of_day
ORDER BY content_kind, part_of_day;

DROP TABLE IF EXISTS mart_by_text_flags;

CREATE TABLE mart_by_text_flags AS
WITH flagged AS (
    SELECT 'is_personal_heur' AS flag, is_personal_heur AS value, views, reactions_total, replies, forwards, er, er_norm
    FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_pinned', is_pinned, views, reactions_total, replies, forwards, er, er_norm
    FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_forwarded', is_forwarded, views, reactions_total, replies, forwards, er, er_norm
    FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_holiday', is_holiday, views, reactions_total, replies, forwards, er, er_norm
    FROM cleansed_posts WHERE NOT is_recent
)
SELECT
    flag,
    value,
    COUNT(*)                                AS posts_count,
    ROUND(AVG(views)::numeric, 1)           AS avg_views,
    ROUND(AVG(reactions_total)::numeric, 2) AS avg_reactions,
    ROUND(AVG(replies)::numeric, 2)         AS avg_replies,
    ROUND(AVG(forwards)::numeric, 2)        AS avg_forwards,
    ROUND(AVG(er)::numeric, 4)              AS er,
    ROUND(AVG(er_norm)::numeric, 4)         AS er_norm
FROM flagged
GROUP BY flag, value
ORDER BY flag, value;