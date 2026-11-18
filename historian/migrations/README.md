# historian/migrations

SQL (and, where a secret is needed, shell) scripts that build the historian database.
`deploy/compose.yaml` mounts this folder at `/docker-entrypoint-initdb.d` in the
TimescaleDB container, which runs the files in name order.

**They run only when the data volume is empty**, on the very first start. Changing a
file here does nothing to an existing database. To rebuild from scratch (this deletes
all historian data):

```sh
make down
docker volume rm pulp_timescaledb-data
make up
```

| File | What it does |
| --- | --- |
| `0001_extensions.sql` | Enables TimescaleDB and pgvector |
| `0002_grafana_reader.sh` | Creates the read-only role Grafana logs in with (`GRAFANA_DB_USER`) |

The historian hypertable and `journal_events` come in WP-03. Number new files after
the last one; never renumber or edit a file that has already been released.
