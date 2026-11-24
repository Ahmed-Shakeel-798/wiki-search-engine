-- Lesson 04: what text should the BM25 index see?
--
-- Lesson 03 indexed only the body, so "Apollo 13" ranked 5th for its own name.
-- Here we compare four versions side by side:
--   A. body only              (lesson 03)
--   B. title + body           (title glued onto the body, one index)
--   C. title x3 + body        (title repeated to give it more weight)
--   D. body score + 2 x title score   (title scored SEPARATELY, then combined)
--
-- B and C use EXPRESSION indexes: built over an expression like (title || ' ' || body)
-- instead of a column, so no extra copy of the text is stored. A query must repeat
-- the exact same expression for Postgres to use that index.
--
-- Run:  docker exec wiki-search-db psql -U postgres -d wiki -f /db/04_search_fields.sql

\timing on
\pset pager off
SET maintenance_work_mem = '256MB';
SET max_parallel_maintenance_workers = 4;

-- ---------------------------------------------------------------------------
-- 1. Build the new indexes (articles_body_bm25 already exists from lesson 03)
-- ---------------------------------------------------------------------------
\echo '\n== 1. Index for B: title + body =='
CREATE INDEX IF NOT EXISTS articles_title_body_bm25 ON articles
  USING bm25 ((title || ' ' || body)) WITH (text_config = 'english');

\echo '\n== Index for C: title x3 + body =='
CREATE INDEX IF NOT EXISTS articles_title3_body_bm25 ON articles
  USING bm25 ((title || ' ' || title || ' ' || title || ' ' || body)) WITH (text_config = 'english');

\echo '\n== Index for D: title only (small and quick) =='
CREATE INDEX IF NOT EXISTS articles_title_bm25 ON articles
  USING bm25 (title) WITH (text_config = 'english');


-- ---------------------------------------------------------------------------
-- 2. Version D on its own, step by step
--
--    a) Take the top 100 CANDIDATES from the title+body index (fast, index scan).
--    b) For each candidate, compute two separate BM25 scores:
--         body_score  using the body index's statistics
--         title_score using the title index's statistics
--       (<@> can score any row, not only rows coming out of an index scan.)
--    c) Re-rank by  body_score + 2 * title_score.  The 2 is a weight you can tune.
--
--    Why this beats C: BM25 scores a text as ONE blob and penalises long texts,
--    so 2-6 title words get drowned in a long body. Scoring the title on its own
--    means a title that matches the query stands out no matter how long the body is.
-- ---------------------------------------------------------------------------
\echo '\n== 2. Version D for "Apollo 13", with both scores visible =='
WITH candidates AS MATERIALIZED (
  SELECT id, title, body
  FROM articles
  ORDER BY (title || ' ' || body) <@> to_bm25query('Apollo 13', 'articles_title_body_bm25')
  LIMIT 100
)
SELECT title,
       round((body  <@> to_bm25query('Apollo 13', 'articles_body_bm25'))::numeric, 2)  AS body_score,
       round((title <@> to_bm25query('Apollo 13', 'articles_title_bm25'))::numeric, 2) AS title_score,
       round(((body  <@> to_bm25query('Apollo 13', 'articles_body_bm25'))
          + 2 * (title <@> to_bm25query('Apollo 13', 'articles_title_bm25')))::numeric, 2) AS combined
FROM candidates
ORDER BY combined
LIMIT 10;


-- ---------------------------------------------------------------------------
-- 3. Helper: top 5 titles for a query under each version, side by side.
--    (A temporary function: it disappears when this session ends.)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.compare(q text)
RETURNS TABLE (rank bigint, a_body text, b_title_body text, c_title3_body text, d_separate_title text)
LANGUAGE sql AS $$
  WITH a AS (
    SELECT title, row_number() OVER (ORDER BY s) AS r FROM (
      SELECT title, body <@> to_bm25query(q, 'articles_body_bm25') AS s
      FROM articles ORDER BY s LIMIT 5) x
  ), b AS (
    SELECT title, row_number() OVER (ORDER BY s) AS r FROM (
      SELECT title, (title || ' ' || body) <@> to_bm25query(q, 'articles_title_body_bm25') AS s
      FROM articles ORDER BY s LIMIT 5) x
  ), c AS (
    SELECT title, row_number() OVER (ORDER BY s) AS r FROM (
      SELECT title, (title || ' ' || title || ' ' || title || ' ' || body)
                    <@> to_bm25query(q, 'articles_title3_body_bm25') AS s
      FROM articles ORDER BY s LIMIT 5) x
  ), d_candidates AS MATERIALIZED (
      SELECT title, body FROM articles
      ORDER BY (title || ' ' || body) <@> to_bm25query(q, 'articles_title_body_bm25') LIMIT 100
  ), d AS (
    SELECT title, row_number() OVER (ORDER BY s) AS r FROM (
      SELECT title, (body <@> to_bm25query(q, 'articles_body_bm25'))
                + 2 * (title <@> to_bm25query(q, 'articles_title_bm25')) AS s
      FROM d_candidates ORDER BY s LIMIT 5) x
  )
  SELECT r, a.title, b.title, c.title, d.title
  FROM a FULL JOIN b USING (r) FULL JOIN c USING (r) FULL JOIN d USING (r)
  ORDER BY r
$$;


-- ---------------------------------------------------------------------------
-- 4. Compare. For each query, ask: is the article you'd EXPECT at the top?
-- ---------------------------------------------------------------------------
\echo '\n== 4a. "Apollo 13"  (expect: Apollo 13) =='
SELECT * FROM pg_temp.compare('Apollo 13');

\echo '\n== 4b. "volcano"  (expect: Volcano) =='
SELECT * FROM pg_temp.compare('volcano');

\echo '\n== 4c. "Albert Einstein"  (expect: Albert Einstein) =='
SELECT * FROM pg_temp.compare('Albert Einstein');

\echo '\n== 4d. "jazz trumpet new orleans"  (a topic, not a title: does boosting titles hurt?) =='
SELECT * FROM pg_temp.compare('jazz trumpet new orleans');

\echo '\n== 4e. "volcano eruption ash aviation"  (a topic, not a title) =='
SELECT * FROM pg_temp.compare('volcano eruption ash aviation');


-- ---------------------------------------------------------------------------
-- 5. Are the indexes really used? Look for "Index Scan using articles_title_body_bm25".
-- ---------------------------------------------------------------------------
\echo '\n== 5. Query plan for the candidate step (B and D) =='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT title FROM articles
ORDER BY (title || ' ' || body) <@> to_bm25query('Apollo 13', 'articles_title_body_bm25')
LIMIT 100;


-- ---------------------------------------------------------------------------
-- 6. What all these indexes cost on disk
-- ---------------------------------------------------------------------------
\echo '\n== 6. Sizes =='
SELECT c.relname AS name, pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
WHERE c.relname IN ('articles', 'articles_body_gin', 'articles_body_bm25', 'articles_title_bm25',
                    'articles_title_body_bm25', 'articles_title3_body_bm25')
ORDER BY pg_relation_size(c.oid) DESC;

\echo '\nNext: pick the version that ranks best, then drop the indexes we no longer need.'
