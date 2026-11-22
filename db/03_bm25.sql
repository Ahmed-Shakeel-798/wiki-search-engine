-- Lesson 03: BM25 ranking with pg_textsearch.
--
-- Run:  docker exec wiki-search-db psql -U postgres -d wiki -f /db/03_bm25.sql

\timing on
\pset pager off

-- ---------------------------------------------------------------------------
-- 1. Build the BM25 index on the article body
--    While building, pg_textsearch counts how often every term appears in every
--    article, how long each article is, and how many articles contain each term.
--    Those three numbers are exactly what the BM25 formula needs.
-- ---------------------------------------------------------------------------
\echo '\n== 1. Building BM25 index on body (takes a little while) =='
SET maintenance_work_mem = '256MB';
SET max_parallel_maintenance_workers = 4;
CREATE INDEX IF NOT EXISTS articles_body_bm25 ON articles
  USING bm25 (body) WITH (text_config = 'english');


-- ---------------------------------------------------------------------------
-- 2. First BM25 search
--    <@> returns a NEGATIVE score, so ascending ORDER BY = best first.
--    Same query as lesson 02, plus "aviation": BM25 does NOT require every word.
--    Articles missing a word still rank, just lower.
-- ---------------------------------------------------------------------------
\echo '\n== 2. BM25 search (note: 4 words, no AND requirement) =='
SELECT id, title,
       round((body <@> 'volcano eruption ash aviation')::numeric, 3) AS score
FROM articles
ORDER BY body <@> 'volcano eruption ash aviation'
LIMIT 10;


-- ---------------------------------------------------------------------------
-- 3. How it runs
--    Look for "Index Scan using articles_body_bm25" and NO separate Sort step:
--    the index hands back rows already in score order and stops after 10
--    (the Block-Max WAND algorithm skips blocks that can't make the top 10).
--    Compare with the "Sort" over every match in lesson 02.
-- ---------------------------------------------------------------------------
\echo '\n== 3. Query plan =='
EXPLAIN (ANALYZE, COSTS OFF)
SELECT id
FROM articles
ORDER BY body <@> 'volcano eruption ash aviation'
LIMIT 10;


-- ---------------------------------------------------------------------------
-- 4. Why BM25 ranks better: rare words count more
--    "the"-like common words appear everywhere and tell us little.
--    A rare word like "trumpet" is a strong signal. BM25 weights each term by
--    how rare it is across all 241k articles (IDF). Try the parts separately:
-- ---------------------------------------------------------------------------
\echo '\n== 4. Common vs rare words =='
\echo '-- "new orleans" alone:'
SELECT title, round((body <@> 'new orleans')::numeric, 3) AS score
FROM articles ORDER BY body <@> 'new orleans' LIMIT 5;

\echo '-- "jazz trumpet new orleans":'
SELECT title, round((body <@> 'jazz trumpet new orleans')::numeric, 3) AS score
FROM articles ORDER BY body <@> 'jazz trumpet new orleans' LIMIT 10;


-- ---------------------------------------------------------------------------
-- 5. A weakness to fix in the next lesson
--    We only indexed the BODY. Searching for a specific article by name can
--    rank it lower than articles that merely mention the name a lot.
-- ---------------------------------------------------------------------------
\echo '\n== 5. Searching for an article by its title =='
SELECT title, round((body <@> 'Apollo 13')::numeric, 3) AS score
FROM articles ORDER BY body <@> 'Apollo 13' LIMIT 10;


-- How big are our two indexes compared with the table?
\echo '\n== Index sizes =='
SELECT relname AS name, pg_size_pretty(pg_relation_size(oid)) AS size
FROM pg_class
WHERE relname IN ('articles', 'articles_body_gin', 'articles_body_bm25')
ORDER BY relname;
