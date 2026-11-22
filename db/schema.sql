-- Articles table: one row per Simple English Wikipedia article
-- (wikimedia/wikipedia, snapshot 20231101.simple, 241,787 articles).
--
-- Safe to re-run: IF NOT EXISTS makes every statement a no-op the second time.
-- Search indexes (BM25, HNSW) are created later, in their own steps, after the data is loaded.

CREATE TABLE IF NOT EXISTS articles (
    -- Wikipedia's own page ID, taken straight from the dataset.
    -- We keep it (instead of generating our own) so results can be traced back to the source.
    id          bigint  PRIMARY KEY,

    url         text    NOT NULL,
    title       text    NOT NULL,

    -- Full plain-text article. BM25 keyword search runs over this column.
    body        text    NOT NULL,

    -- Computed by the loader. Used to pick the longest articles for embedding,
    -- and handy for sanity checks.
    word_count  integer NOT NULL CHECK (word_count >= 0),

    -- 384 numbers from the all-MiniLM-L6-v2 model.
    -- NULL for most rows: only ~25k articles get embedded.
    embedding   vector(384)
);
