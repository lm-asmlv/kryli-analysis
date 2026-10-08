-- ============================================================
-- Data Quality Report for cleansed_posts
-- Each row: check name, number of problems found, status
-- Status: PASS (0 problems), INFO (expected/not an error), FAIL (real issue)
-- ============================================================

SET client_encoding = 'UTF8';

WITH checks AS (

    -- 1. Duplicates by post_id
    SELECT '1. duplicate post_id' AS check_name,
           COUNT(*) AS problems,
           'FAIL' AS fail_status
    FROM (SELECT post_id FROM cleansed_posts GROUP BY post_id HAVING COUNT(*) > 1) t

    UNION ALL

    -- 2. NULL in critical fields
    SELECT '2. null date_time / views',
           COUNT(*) FILTER (WHERE date_time IS NULL OR views IS NULL),
           'FAIL'
    FROM cleansed_posts

    UNION ALL

    -- 3. Negative metrics
    SELECT '3. negative metrics',
           COUNT(*) FILTER (WHERE views < 0 OR reactions_total < 0
                               OR forwards < 0 OR replies < 0),
           'FAIL'
    FROM cleansed_posts

    UNION ALL

    -- 4. reactions_total consistency with breakdown
    SELECT '4. reactions_total != sum(breakdown)',
           COUNT(*) FILTER (
               WHERE reactions_breakdown IS NOT NULL
                 AND (reactions_breakdown->>'total')::numeric
                     <> (SELECT COALESCE(SUM(value::numeric),0)
                         FROM jsonb_each_text(reactions_breakdown->'reactions'))
           ),
           'FAIL'
    FROM cleansed_posts

    UNION ALL

    -- 5. Share of NULL in reactions_total (threshold 5%)
    SELECT '5. null reactions_total over 5%',
           CASE WHEN (COUNT(*) FILTER (WHERE reactions_total IS NULL)::numeric
                      / NULLIF(COUNT(*),0)) > 0.05
                THEN 1 ELSE 0 END,
           'FAIL'
    FROM cleansed_posts

    UNION ALL

    -- 6. Negative time_since_prev_post
    SELECT '6. time_since_prev_post < 0',
           COUNT(*) FILTER (WHERE time_since_prev_post < 0),
           'FAIL'
    FROM cleansed_posts

    UNION ALL

    -- 7. Date gaps: more than 14 days between consecutive posts
    SELECT '7. date gap over 14 days (info)',
           COUNT(*) FILTER (WHERE time_since_prev_post > 336),
           'INFO'
    FROM cleansed_posts

    UNION ALL

    -- 8. Zero increment: no posts in last 7 days (info, airflow placeholder)
    SELECT '8. zero increment last 7 days (info)',
           CASE WHEN COUNT(*) FILTER (
                    WHERE date_time > (SELECT MAX(date_time) FROM cleansed_posts)
                                       - INTERVAL '7 days') = 0
                THEN 1 ELSE 0 END,
           'INFO'
    FROM cleansed_posts

    UNION ALL

    -- 9. text_length mismatch
    SELECT '9. text_length != LENGTH(text)',
           COUNT(*) FILTER (WHERE text_length <> COALESCE(LENGTH(text),0)),
           'FAIL'
    FROM cleansed_posts

    UNION ALL

    -- 10. Recent posts within 7-day window (info, excluded from marts)
    SELECT '10. posts younger than 7 days (info)',
           COUNT(*) FILTER (WHERE is_recent),
           'INFO'
    FROM cleansed_posts

)
SELECT
    check_name,
    problems,
    CASE
        WHEN fail_status = 'INFO' THEN 'INFO'
        WHEN problems = 0         THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM checks
ORDER BY check_name;