# Mealie (Home Assistant add-on)

Pinned to `ghcr.io/mealie-recipes/mealie:v3.1.2`.

- Default port: 9925 (host) → 9000 (container)
- Data is stored in `/data/mealie` (included in HA backups)
- Set `allow_signup: true` in options to enable self-registration, or use the default admin credentials you set via options.

Docs:
- Docker/SQLite example and volume: `/app/data`. We map this into `/data/mealie` for HA backups.  
- Backend env reference: `ALLOW_SIGNUP`, `BASE_URL`, DB settings (`DB_ENGINE`, `POSTGRES_*`), etc.  
