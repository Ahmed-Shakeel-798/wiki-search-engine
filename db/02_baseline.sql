-- Lesson 02: keyword search with PostgreSQL's BUILT-IN full-text search.
-- This is the "before" picture we'll compare BM25 against in lesson 03.
--
-- Run:  docker exec wiki-search-db psql -U postgres -d wiki -f /db/02_baseline.sql

\timing on
\pset pager off

-- ---------------------------------------------------------------------------
-- 1. How Postgres sees text
--    to_tsvector turns text into lexemes: lower-cased, stemmed, stop words removed.
--    Notice "erupted" and "eruptions" both become 'erupt', and "the"/"in" vanish.
-- ---------------------------------------------------------------------------
\echo '\n== 1. Text -> lexemes =='
SELECT to_tsvector('english', 'The volcano erupted, and eruptions continued in 1980.');

-- A query goes through the same process. plainto_tsquery joins words with & (AND).
SELECT plainto_tsquery('english', 'volcano eruption ash cloud');


-- ---------------------------------------------------------------------------
-- 2. Search with NO index
--    Postgres must convert every one of the 241,787 bodies to a tsvector, on the fly,
--    for every query. Watch the time.
-- ---------------------------------------------------------------------------
\echo '\n== 2. No index (full scan) =='
DROP INDEX IF EXISTS articles_body_gin;

SELECT id, title,
       ts_rank(to_tsvector('english', body), q) AS rank
FROM articles, plainto_tsquery('english', 'volcano eruption ash cloud') AS q
WHERE to_tsvector('english', body) @@ q
ORDER BY rank DESC
LIMIT 10;


-- ---------------------------------------------------------------------------
-- 3. Add a GIN index
--    A GIN index is an "inverted index": for each lexeme, the list of rows containing it.
--    Finding matches becomes a lookup instead of a scan.
-- ---------------------------------------------------------------------------
\echo '\n== 3. Building GIN index (takes a little while) =='
SET maintenance_work_mem = '256MB';
CREATE INDEX articles_body_gin ON articles USING gin (to_tsvector('english', body));

\echo '\n== Same query, with the GIN index =='
SELECT id, title,
       ts_rank(to_tsvector('english', body), q) AS rank
FROM articles, plainto_tsquery('english', 'volcano eruption ash cloud') AS q
WHERE to_tsvector('english', body) @@ q
ORDER BY rank DESC
LIMIT 10;

-- EXPLAIN ANALYZE shows HOW Postgres ran it. Look for "Bitmap Index Scan on articles_body_gin"
-- (the fast lookup) and then a "Sort": ts_rank still has to score EVERY matching row
-- before it can pick the top 10. With common words that's a lot of rows.
\echo '\n== Query plan =='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT id
FROM articles, plainto_tsquery('english', 'volcano eruption ash cloud') AS q
WHERE to_tsvector('english', body) @@ q
ORDER BY ts_rank(to_tsvector('english', body), q) DESC
LIMIT 10;


-- ---------------------------------------------------------------------------
-- 4. The AND problem
--    plainto_tsquery requires ALL words. One word the article doesn't use
--    and a perfectly relevant article disappears from the results.
-- ---------------------------------------------------------------------------
\echo '\n== 4. One extra word can hide a relevant article =='
SELECT
  to_tsvector('english', 'The volcano erupted and its ash grounded flights')
    @@ plainto_tsquery('english', 'volcano eruption ash')          AS three_words_match,
  to_tsvector('english', 'The volcano erupted and its ash grounded flights')
    @@ plainto_tsquery('english', 'volcano eruption ash aviation') AS plus_aviation_match;

-- Stemming has limits too: "volcanic" and "volcano" become different lexemes,
-- so they don't match each other. (Semantic search will handle this later.)
SELECT to_tsvector('english', 'volcanic') AS volcanic, to_tsvector('english', 'volcano') AS volcano;

-- How many articles match as you add words? (AND shrinks the result set fast.)
SELECT 'volcano'                     AS query, count(*) FROM articles WHERE to_tsvector('english', body) @@ plainto_tsquery('english', 'volcano')
UNION ALL
SELECT 'volcano eruption',             count(*) FROM articles WHERE to_tsvector('english', body) @@ plainto_tsquery('english', 'volcano eruption')
UNION ALL
SELECT 'volcano eruption ash',         count(*) FROM articles WHERE to_tsvector('english', body) @@ plainto_tsquery('english', 'volcano eruption ash')
UNION ALL
SELECT 'volcano eruption ash aviation', count(*) FROM articles WHERE to_tsvector('english', body) @@ plainto_tsquery('english', 'volcano eruption ash aviation');
