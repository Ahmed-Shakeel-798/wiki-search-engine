"""Load the Simple English Wikipedia snapshot into the articles table.

Usage:
    python scripts/load.py               # all 241,787 articles
    python scripts/load.py --limit 1000  # quick test run
    python scripts/load.py --parquet FILE  # use a file you already downloaded (skips download)

Safe to re-run: articles that are already in the table are skipped, never overwritten.
"""
import argparse
import hashlib
import os
import time
from pathlib import Path

import psycopg
import pyarrow.parquet as pq
from dotenv import load_dotenv
from huggingface_hub import hf_hub_download

# --- Which data we load -------------------------------------------------------
# Pinned to one exact version of the dataset so every run loads identical data.
DATASET_REPO = "wikimedia/wikipedia"
DATASET_REVISION = "3e1f92c331f318af862b87e2319ed5dc26d80f5d"
DATASET_FILE = "20231101.simple/train-00000-of-00001.parquet"
# SHA-256 fingerprint of that file. If the download doesn't match, we stop.
DATASET_SHA256 = "31bded16768a47c286becd292079122f5d7d4397a17b87d4250a00ccd581e6f0"

BATCH_SIZE = 2000  # rows read from the Parquet file at a time

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT / ".env")
DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/wiki"
)


def download_dataset() -> Path:
    """Download the Parquet file (cached after the first run) and verify it."""
    print("Fetching dataset (first run downloads it, later runs use the cache)...")
    path = Path(
        hf_hub_download(
            repo_id=DATASET_REPO,
            repo_type="dataset",
            revision=DATASET_REVISION,
            filename=DATASET_FILE,
        )
    )
    sha = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            sha.update(chunk)
    if sha.hexdigest() != DATASET_SHA256:
        raise RuntimeError(f"Checksum mismatch for {path}: the file is corrupt or changed.")
    print(f"Dataset OK: {path}")
    return path


def clean(text: str) -> str:
    # Postgres text columns cannot store the NUL character, so strip it.
    return text.replace("\x00", "")


def iter_articles(path: Path, limit: int | None):
    """Yield (id, url, title, body, word_count) one article at a time.

    Reads the file in batches so the whole dataset never sits in memory.
    """
    count = 0
    parquet = pq.ParquetFile(path)
    for batch in parquet.iter_batches(batch_size=BATCH_SIZE, columns=["id", "url", "title", "text"]):
        for row in batch.to_pylist():
            body = clean(row["text"])
            yield (int(row["id"]), row["url"], clean(row["title"]), body, len(body.split()))
            count += 1
            if limit is not None and count >= limit:
                return


def main():
    parser = argparse.ArgumentParser(description="Load Wikipedia articles into Postgres.")
    parser.add_argument("--limit", type=int, help="only load the first N articles (for testing)")
    parser.add_argument("--parquet", type=Path, help="path to an already-downloaded Parquet file")
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be a positive number")

    path = args.parquet or download_dataset()
    started = time.perf_counter()

    with psycopg.connect(DATABASE_URL) as conn:
        # 1. A temporary staging table that disappears when this transaction ends.
        conn.execute("""
            CREATE TEMP TABLE staging (
                id bigint, url text, title text, body text, word_count int
            ) ON COMMIT DROP
        """)

        # 2. COPY streams rows into Postgres far faster than one INSERT per row.
        read = 0
        with conn.cursor().copy(
            "COPY staging (id, url, title, body, word_count) FROM STDIN"
        ) as copy:
            for article in iter_articles(path, args.limit):
                copy.write_row(article)
                read += 1
                if read % 20000 == 0:
                    print(f"  read {read:,} articles...")

        # 3. Move rows into the real table, skipping IDs that are already there.
        inserted = conn.execute("""
            INSERT INTO articles (id, url, title, body, word_count)
            SELECT id, url, title, body, word_count FROM staging
            ON CONFLICT (id) DO NOTHING
        """).rowcount
        # Leaving the `with` block commits everything in one go:
        # either all rows land, or (on any error) none do.

    with psycopg.connect(DATABASE_URL, autocommit=True) as conn:
        # 4. Refresh the statistics the query planner uses to choose good plans.
        conn.execute("ANALYZE articles")
        total = conn.execute("SELECT count(*) FROM articles").fetchone()[0]

    elapsed = time.perf_counter() - started
    print(f"Read {read:,} | inserted {inserted:,} new | table now has {total:,} | {elapsed:.1f}s")


if __name__ == "__main__":
    main()
