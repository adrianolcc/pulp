#!/bin/sh
# A read-only login role for Grafana. Grafana only draws trends, so it must not be
# able to write to the historian or the journal.
#
# This is a shell script rather than SQL because the password comes from .env
# (GRAFANA_DB_PASSWORD), and the init step passes environment variables to shell
# scripts only. psql's -v variables quote the values, so a password with quotes
# in it cannot break the SQL.
set -eu

psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -v reader="$GRAFANA_DB_USER" -v reader_password="$GRAFANA_DB_PASSWORD" \
    -v owner="$POSTGRES_USER" -v db="$POSTGRES_DB" <<'SQL'
CREATE ROLE :"reader" LOGIN PASSWORD :'reader_password';
GRANT CONNECT ON DATABASE :"db" TO :"reader";
GRANT USAGE ON SCHEMA public TO :"reader";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"reader";
-- Tables the owner creates later (WP-03 onwards) are readable too, without
-- a grant in every migration.
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public
    GRANT SELECT ON TABLES TO :"reader";
SQL
