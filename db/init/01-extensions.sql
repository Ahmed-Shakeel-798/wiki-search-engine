-- Runs once, the first time the database volume is initialised.
-- Versions are pinned so a newer image can't silently change behaviour.
CREATE EXTENSION IF NOT EXISTS pg_textsearch VERSION '1.5.1';
CREATE EXTENSION IF NOT EXISTS vector VERSION '0.8.7';
