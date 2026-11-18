-- Extensions for the historian database.
-- timescaledb: hypertables for telemetry and the event journal (tables in WP-03).
-- vector (pgvector): document embeddings for search (WP-18).
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS vector;
