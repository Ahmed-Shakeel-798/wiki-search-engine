# Wiki Search Engine

A Wikipedia search engine built entirely within PostgreSQL, using BM25 keyword matching, vector embeddings, and reciprocal rank fusion, with results served through a FastAPI backend.

## Goals

- **Keyword search** across **241,787** Wikipedia articles using BM25 ranking
- **Semantic search** across **25,000** articles using vector embeddings
- **Hybrid ranking** that combines keyword and semantic results with Reciprocal Rank Fusion (RRF)
- Everything lives in **one PostgreSQL database**: no separate search engine or vector store
- Results served through a **FastAPI** backend

## Architecture

```
            ┌──────────────┐
  query ──▶ │   FastAPI    │
            └──────┬───────┘
                   │
        ┌──────────▼───────────┐
        │      PostgreSQL      │
        │                      │
        │  BM25 keyword index  │──┐
        │  Vector embeddings   │──┼──▶ Reciprocal Rank Fusion ──▶ ranked results
        └──────────────────────┘  │
```

## Getting started

### 1. Start PostgreSQL

Requires Docker. The database image bundles PostgreSQL 17, pg_textsearch 1.5.1 and pgvector 0.8.7.

```bash
docker compose up -d
```

The first start downloads a ~4 GB image and creates both extensions automatically (`db/init/01-extensions.sql`).

### 2. Check the extensions loaded

```bash
docker exec -it wiki-search-db psql -U postgres -d wiki -c "SELECT extname, extversion FROM pg_extension;"
```

You should see `pg_textsearch | 1.5.1` and `vector | 0.8.7`.

Connection string: `postgresql://postgres:postgres@localhost:5432/wiki`

### 3. Create the schema

macOS / Linux:

```bash
docker exec -i wiki-search-db psql -U postgres -d wiki < db/schema.sql
```

Windows PowerShell:

```powershell
Get-Content db/schema.sql | docker exec -i wiki-search-db psql -U postgres -d wiki
```

Creates the `articles` table. Safe to run more than once.

### 4. Set up Python

Requires Python 3.11 or newer.

macOS / Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Windows PowerShell:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

### 5. Load the articles

Downloads the Simple English Wikipedia snapshot (20231101.simple) from Hugging Face and loads it into `articles`.

```bash
python scripts/load.py --limit 1000   # quick test
python scripts/load.py                # all 241,787 articles
```

Safe to re-run: articles already in the table are skipped.

## Status

🚧 Work in progress.
