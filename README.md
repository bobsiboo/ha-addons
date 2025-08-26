# Home Assistant Add-ons — Donetick (Pinned)

This repository contains a **custom Home Assistant add-on** that wraps the upstream
[`donetick/donetick`](https://hub.docker.com/r/donetick/donetick) image and pins it
to a **specific version** for stability.

> **Not affiliated** with Donetick. This repo only provides HA add-on metadata.

---

## Add this repository to Home Assistant

1. Home Assistant → **Settings → Add-ons → Add-on Store**
2. Top-right **⋮ → Repositories**
3. Add: `https://github.com/bobsiboo/ha-addons`
4. Open **Donetick** → **Install** → **Start**
5. **Open Web UI** (defaults to port `2021`)

---

## Add-on details

- **Image:** `donetick/donetick:v0.1.53` (pinned)
- **Architectures:** `amd64`, `aarch64`
- **Web UI:** `http://[HOST]:2021`

### Environment (pre-configured)

These are set in the add-on:

```text
DT_ENV=selfhosted
DT_SQLITE_PATH=/data/donetick.db
