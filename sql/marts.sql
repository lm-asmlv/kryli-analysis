-- ============================================================
-- MARTS: ВСЕ ВИТРИНЫ В ОДНОМ ФАЙЛЕ (чистый, без дублей)
-- Канал @krylikryli · источник: cleansed_posts
-- Фильтр: только посты старше 7 дней (NOT is_recent).
--
-- Состав (запускать целиком):
--   0. mart_by_hour             — по часу публикации
--   1. mart_by_weekday          — по дню недели
--   2. mart_by_content_type     — по типу медиа
--   3. mart_by_text_flags       — по флагам
--   4. mart_by_interval         — по интервалу между постами
--   5. mart_by_text_length      — по длине текста (терцили)
--   6. mart_by_combination      — тип текста × часть дня
--   7. mart_by_factor_vs_metric — ФАКТОР × МЕТРИКА (3 метрики раздельно)
--   8. diag_is_forwarded        — диагностика флага is_forwarded
--
-- КОНТРАКТ КОЛОНОК (единый для SQL ↔ notebooks):
--   * ER-метрика называетcя ВСЕГДА `mean_er` (не `er`!).
--   * Рядом всегда есть `median_er` (устойчив к выбросам).
-- ============================================================
--
-- ИСПРАВЛЕНО vs предыдущей версии:
--   * УБРАН дублирующий блок "VITRINA mart_by_factor_vs_metric".
--   * УБРАНЫ промежуточные таблицы mart_factor_*.
--   * ЕДИНЫЙ источник по часам: mart_by_hour (+ factor 'hour' внутри
--     mart_by_factor_vs_metric). Отдельной mart_factor_hour больше нет.
--   * ДОБАВЛЕНА метрика forwards_per_reply — "репостят vs обсуждают".
--
-- Во всех витринах рядом с MEAN добавлены MEDIAN-метрики (устойчивы
-- к выбросам — см. чек-лист, п. P1.7).
-- ============================================================

SET client_encoding = 'UTF8';

-- ------------------------------------------------------------
-- Уборка старых промежуточных таблиц (наследие прошлых запусков)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_factor_part_of_day;
DROP TABLE IF EXISTS mart_factor_hour;
DROP TABLE IF EXISTS mart_factor_media_type;
DROP TABLE IF EXISTS mart_factor_text_length;
DROP TABLE IF EXISTS mart_factor_flags;
DROP TABLE IF EXISTS mart_factor_interval;

-- ------------------------------------------------------------
-- 0. mart_by_hour — вовлечённость по часу публикации
--    ЕДИНЫЙ источник истины по часам.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_hour;
CREATE TABLE mart_by_hour AS
SELECT
    hour,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY reactions_total)::numeric, 2) AS median_reactions,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY replies)::numeric, 2)         AS median_replies,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY forwards)::numeric, 2)        AS median_forwards,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4)              AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY hour
ORDER BY hour;

-- ------------------------------------------------------------
-- 1. mart_by_weekday — по дню недели (0=Вс … 6=Сб)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_weekday;
CREATE TABLE mart_by_weekday AS
SELECT
    weekday,
    CASE weekday
        WHEN 0 THEN 'Sun' WHEN 1 THEN 'Mon' WHEN 2 THEN 'Tue'
        WHEN 3 THEN 'Wed' WHEN 4 THEN 'Thu' WHEN 5 THEN 'Fri'
        WHEN 6 THEN 'Sat'
    END                                                 AS weekday_name,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY weekday
ORDER BY weekday;

-- ------------------------------------------------------------
-- 2. mart_by_content_type — по типу медиа
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_content_type;
CREATE TABLE mart_by_content_type AS
SELECT
    COALESCE(media_type, 'none')                        AS media_type,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY COALESCE(media_type, 'none')
ORDER BY posts_count DESC;

-- ------------------------------------------------------------
-- 3. mart_by_text_flags — по статусным/текстовым флагам
--    (unpivot через UNION ALL по каждому флагу)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_text_flags;
CREATE TABLE mart_by_text_flags AS
WITH flagged AS (
    SELECT 'is_personal_heur' AS flag, is_personal_heur AS value, views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_pinned',    is_pinned,    views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_forwarded', is_forwarded, views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
    UNION ALL
    SELECT 'is_holiday',   is_holiday,   views, reactions_total, replies, forwards, er, er_norm FROM cleansed_posts WHERE NOT is_recent
)
SELECT
    flag,
    value,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM flagged
GROUP BY flag, value
ORDER BY flag, value;

-- ------------------------------------------------------------
-- 4. mart_by_interval — по промежутку между постами
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_interval;
CREATE TABLE mart_by_interval AS
SELECT
    CASE
        WHEN time_since_prev_post IS NULL THEN 'first_post'
        WHEN time_since_prev_post < 6     THEN 'lt_6h'
        WHEN time_since_prev_post < 24    THEN '6_24h'
        WHEN time_since_prev_post < 72    THEN '24_72h'
        ELSE 'gt_72h'
    END                                                 AS interval_bucket,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY interval_bucket
ORDER BY posts_count DESC;

-- ------------------------------------------------------------
-- 5. mart_by_text_length — по длине текста (терцили)
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_text_length;
CREATE TABLE mart_by_text_length AS
SELECT
    length_bucket,
    COUNT(*)                                            AS posts_count,
    ROUND(AVG(text_length)::numeric, 1)                 AS mean_text_length,
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY length_bucket
ORDER BY mean_text_length;

-- ------------------------------------------------------------
-- 6. mart_by_combination — тип текста × часть дня
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
    ROUND(AVG(views)::numeric, 1)                       AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)             AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)                     AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)                    AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)                          AS mean_er,
    ROUND(AVG(er_norm)::numeric, 4)                     AS mean_er_norm,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY content_kind, part_of_day
ORDER BY content_kind, part_of_day;

-- ------------------------------------------------------------
-- 7. mart_by_factor_vs_metric — ГЛАВНАЯ ДЛЯ ТЗ
--    Для каждого фактора считаем ОТДЕЛЬНО:
--    реакции / комментарии(replies) / репосты(forwards).
--    Long-формат: (factor, factor_value) → метрики.
--
--    Каждый (factor, factor_value) — РОВНО ОДИН раз (дедуп через
--    UNION ALL по очищенным подзапросам, без промежуточных таблиц).
-- ------------------------------------------------------------
DROP TABLE IF EXISTS mart_by_factor_vs_metric;
CREATE TABLE mart_by_factor_vs_metric AS
WITH src AS (
    SELECT 'part_of_day'::text AS factor,
           CASE
               WHEN hour BETWEEN 0  AND 5  THEN 'night'
               WHEN hour BETWEEN 6  AND 11 THEN 'morning'
               WHEN hour BETWEEN 12 AND 17 THEN 'day'
               ELSE 'evening'
           END::text AS factor_value,
           reactions_total, replies, forwards, er, views
    FROM cleansed_posts WHERE NOT is_recent

    UNION ALL
    SELECT 'media_type', COALESCE(media_type, 'none'),
           reactions_total, replies, forwards, er, views
    FROM cleansed_posts WHERE NOT is_recent

    UNION ALL
    SELECT 'content_kind',
           CASE WHEN is_personal_heur THEN 'personal' ELSE 'promo' END,
           reactions_total, replies, forwards, er, views
    FROM cleansed_posts WHERE NOT is_recent

    UNION ALL
    SELECT 'length_bucket', length_bucket,
           reactions_total, replies, forwards, er, views
    FROM cleansed_posts WHERE NOT is_recent

    UNION ALL
    SELECT 'interval_bucket',
           CASE
               WHEN time_since_prev_post IS NULL THEN 'first_post'
               WHEN time_since_prev_post < 6     THEN 'lt_6h'
               WHEN time_since_prev_post < 24    THEN '6_24h'
               WHEN time_since_prev_post < 72    THEN '24_72h'
               ELSE 'gt_72h'
           END,
           reactions_total, replies, forwards, er, views
    FROM cleansed_posts WHERE NOT is_recent

    UNION ALL
    SELECT 'is_holiday', is_holiday::text,
           reactions_total, replies, forwards, er, views
    FROM cleansed_posts WHERE NOT is_recent
)
SELECT
    factor,
    factor_value,
    COUNT(*)                                                                        AS posts_count,
    ROUND(AVG(reactions_total)::numeric, 3)                                         AS mean_reactions,
    ROUND(AVG(replies)::numeric, 3)                                                 AS mean_replies,
    ROUND(AVG(forwards)::numeric, 3)                                                AS mean_forwards,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY reactions_total)::numeric, 3) AS median_reactions,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY replies)::numeric, 3)         AS median_replies,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY forwards)::numeric, 3)        AS median_forwards,
    ROUND((1000.0 * AVG(reactions_total) / NULLIF(AVG(views), 0))::numeric, 3)      AS reactions_per_1k_views,
    ROUND((1000.0 * AVG(replies)        / NULLIF(AVG(views), 0))::numeric, 3)      AS replies_per_1k_views,
    ROUND((1000.0 * AVG(forwards)       / NULLIF(AVG(views), 0))::numeric, 3)      AS forwards_per_1k_views,
    -- "репостят vs обсуждают": >1 — форварды перевешивают обсуждение.
    -- Считается ПО ГРУППЕ (AVG(forwards)/AVG(replies)); при replies=0 в группе
    -- (NULLIF) значение = NULL. Метрика называетcя forwards_per_reply (по ТЗ).
    ROUND((AVG(forwards) / NULLIF(AVG(replies), 0))::numeric, 3)                    AS forwards_per_reply,
    ROUND(AVG(er)::numeric, 4)                                                      AS mean_er,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4)              AS median_er
FROM src
GROUP BY factor, factor_value
ORDER BY factor, posts_count DESC;

-- ------------------------------------------------------------
-- 8. diag_is_forwarded — диагностика флага is_forwarded
--    Семантика флага неоднозначна (см. README / conclusions):
--    в дампе is_forwarded=true встречается у постов самой персоны,
--    что может означать, что Telethon отдаёт forward там, где это
--    НЕ перепост. Витрина помогает увидеть разницу в метриках.
-- ------------------------------------------------------------
DROP TABLE IF EXISTS diag_is_forwarded;
CREATE TABLE diag_is_forwarded AS
SELECT
    is_forwarded,
    COUNT(*)                                 AS posts_count,
    ROUND(AVG(views)::numeric, 1)            AS mean_views,
    ROUND(AVG(reactions_total)::numeric, 2)  AS mean_reactions,
    ROUND(AVG(replies)::numeric, 2)          AS mean_replies,
    ROUND(AVG(forwards)::numeric, 2)         AS mean_forwards,
    ROUND(AVG(er)::numeric, 4)               AS mean_er,
    ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY er)::numeric, 4) AS median_er
FROM cleansed_posts
WHERE NOT is_recent
GROUP BY is_forwarded
ORDER BY is_forwarded;

-- ============================================================
-- ПРОВЕРКА (запусти отдельно):
--   SELECT COUNT(*) FROM mart_by_hour;             -- ожидаем 24
--   SELECT factor, COUNT(*) FROM mart_by_factor_vs_metric GROUP BY factor;
--   SELECT EXISTS (SELECT 1 FROM information_schema.tables
--                  WHERE table_name LIKE 'mart_factor_%');  -- должно быть false
--
--   -- Контракт колонок: везде должна быть mean_er (НЕ er):
--   SELECT table_name, column_name FROM information_schema.columns
--   WHERE table_schema='public' AND table_name LIKE 'mart%'
--     AND column_name = 'er';                        -- ожидаем 0 строк
-- ============================================================
