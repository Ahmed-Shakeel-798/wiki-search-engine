# PostgreSQL Hybrid Search Course – Keyword (BM25) + Vector Retrieval

## Lesson 01: Setup, Concepts & Data Loading (Flashcards)

### Tools & Concepts

**Q: Which extensions does the course use?**\
A: **`pg_textsearch`** for keyword search ranked with **BM25**, and **`pgvector`** for storing and searching **vector embeddings**.

**Q: What is the difference between matching and ranking?**\
A: **Matching** decides *which* documents qualify. **Ranking** decides the *order* they appear in.

**Q: How does `pg_textsearch` do matching and ranking?**\
A: **Boolean conditions** decide which rows qualify, and the **BM25 score** orders them.

**Q: What is BM25?**\
A: **BM25 (Best Matching 25)** is a ranking formula that scores how relevant a document is to a keyword query. It is the standard ranking method in Elasticsearch and Lucene. Its score depends on three factors:
1. **Term frequency:** a word that appears more often scores higher, but each repeat adds less (saturation).
2. **Inverse document frequency:** rare words count for more than common ones.
3. **Length normalization:** a short, focused document beats a long one that mentions the word once.

### Table Design

**Q: Why use Wikipedia's IDs instead of generating our own?**\
A: Every row traces back to its source article, and re-running the loader can't create duplicates, because the same article always gets the same ID.

**Q: Why are the text columns `NOT NULL`?**\
A: An article with no title or body is broken data. Postgres rejects it at load time, so it never reaches search results.

**Q: Why store `word_count` instead of calculating it on each query?**\
A: It's used to sort articles and pick the 25k longest ones to embed. Counting the words in 241k articles on every query would be slow.

**Q: Why is the `embedding` column `vector(384)`?**\
A: 384 is exactly the size of the model's output, so Postgres rejects a vector of the wrong length. The column starts as NULL, which costs almost nothing, and the embedding script fills it in later.

**Q: What does the 384-number vector represent?**\
A: The overall *meaning* of the **whole article**, as one vector per row. It is not one vector per word. Texts with similar meanings get vectors that are close together.

**Q: What is the input limit of embedding models, and how is it handled?**\
A: Embedding models accept only a limited length of text, and anything beyond the limit is cut off, so a long article's vector mostly reflects its opening. The fix is **chunking**: split the article into pieces and embed each piece separately.

### Search Indexes

**Q: What is a search index?**\
A: A database index built for a special kind of lookup:
- **BM25 index:** an **inverted index** that maps each word to the articles containing it.
- **Vector index (HNSW or IVFFlat):** finds the nearest vectors without comparing the query against every row. It is **approximate**: very fast, but it can occasionally miss a true best match.

**Q: What happens to queries without a search index?**\
A: Every query scans the whole table. Indexes keep queries fast as the data grows.

**Q: Are indexes updated when the data changes?**\
A: Yes. Postgres updates them automatically on every insert, update and delete, which slows down writes.

**Q: Why build the indexes after the bulk load?**\
A: Building an index once over the finished data is much faster than updating it 241k times during the load.

### Data Loading Patterns

**Q: Why pin the dataset version and verify its checksum?**\
A: Pinning a fixed snapshot makes results **reproducible**. Checking the checksum catches corrupted or unexpected files before anything is loaded.

**Q: Why read the data in batches?**\
A: Reading a fixed number of rows at a time (here, 2,000) keeps memory use constant, whatever the file size.

**Q: Why use `COPY` instead of `INSERT` for bulk loads?**\
A: `COPY` streams many rows in one command and is much faster than thousands of separate `INSERT`s.

**Q: Why load into a staging table first?**\
A: Rows go into a temporary table, then they are merged into the real table, skipping IDs that already exist (`INSERT ... ON CONFLICT DO NOTHING`). This makes the loader **idempotent**: running it twice gives the same result as running it once.

**Q: Why do the merge in a single transaction?**\
A: For **atomicity** (the "A" in ACID): if anything fails, everything is rolled back, so the table is never left half-loaded.

**Q: Why run `ANALYZE` after a large load?**\
A: It refreshes the statistics that the **query planner** uses to choose execution plans. Stale statistics can lead to slow plans.

**Q: What is the NUL-character gotcha?**\
A: Postgres `text` columns can't store NUL (`\0`) characters. Strip them from the data before loading, or the load fails.

## Lesson 02: Built-in Full-Text Search (Flashcards)

**Q: What does `to_tsvector()` do?**\
A: Turns document text into **lexemes**: lower-cased, stemmed, with stop words removed. For example, "erupted" and "eruptions" both become `erupt`, and "the" is dropped.

**Q: What does `plainto_tsquery()` do?**\
A: Turns the user's search text into a query condition, joining the words with `&` (AND). Use `websearch_to_tsquery()` for phrases and `OR`.

**Q: What does `@@` do?**\
A: It is the match operator: it returns true if a `tsvector` satisfies a `tsquery`.

**Q: What does `ts_rank()` do?**\
A: Scores how relevant each matching row is, based on lexeme frequency. It doesn't understand meaning.

**Q: What is a GIN index?**\
A: A **Generalized Inverted Index**: it maps each lexeme to the rows that contain it, so matching becomes a lookup instead of a full table scan.

**Q: Does GIN speed up ranking?**\
A: No. It speeds up **matching** only. `ts_rank()` still scores *every* matching row, and the results are then sorted before `LIMIT` applies. This is slow when a query matches many rows. In `EXPLAIN ANALYZE`, look for a `Bitmap Index Scan` followed by a `Sort`.

**Q: What are the trade-offs of a GIN index?**\
A: Reads get faster. Writes get slower, because the index must be updated too, and the index takes extra disk space.

**Q: What are the weaknesses of built-in full-text search?**\
A:
- **The AND problem:** every word must appear, so one extra word in the query can hide a relevant article.
- **Stemming limits:** "volcanic" and "volcano" become different lexemes, so they don't match. Semantic search fixes this.

**Q: How does full-text search differ from `=` and `LIKE`?**\
A:

| | `=` | `LIKE '%word%'` | Full-text search (`@@`) |
|---|---|---|---|
| Matches | The whole value exactly | Any substring | Whole words (lexemes) |
| Stemming ("erupted" finds "eruption") | No | No | Yes |
| Case-insensitive | No | No (use `ILIKE`) | Yes |
| Ranking | No | No | Yes (`ts_rank`) |
| Index | B-tree | A leading `%` can't use a B-tree, so it scans the whole table (`pg_trgm` + GIN can help) | GIN |

- `LIKE '%cat%'` also matches "category". Full-text search matches whole words only.

**Q: Why use `SET maintenance_work_mem` before `CREATE INDEX`?**\
A: It gives the index build more memory, which makes it faster.
