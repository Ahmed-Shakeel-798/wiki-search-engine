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

## Status

🚧 Work in progress.
