# openclaw-panel

A small Rails panel for a docker-compose OpenClaw install on a NAS. Open it
from a phone or laptop over Tailscale instead of SSHing in to run CLI commands.

- **Status**: gateway health, crash-loop detection, recognised problems with
  one-click fixes, Restart / Stop / Repair (`doctor --repair`) / Recreate.
- **Open Control UI**: mints a one-time owner link (`openclaw dashboard --json`),
  so no token to paste and no pairing to approve.
- **Devices**: approve or reject device pairing requests and chat (Telegram) pairing codes.
- **Config**: edit `openclaw.json`. Every save goes through `openclaw config validate`
  first, and previous versions are kept so you can restore one.
- **Access**: `gateway.publicOrigin`, `controlUi.allowedOrigins` and `trustedProxies`.
  These cause the blank page behind Caddy, and the panel detects the proxy IP from the logs.
- **Updates**: pull, or pin a release via `OPENCLAW_IMAGE` in `.env`. A failed
  update pins the previous version.
- **Env** (`.env` tokens), **Console** (any `openclaw …` command), **History**.
- **Watchdog**: restarts a gateway that hangs (Docker only restarts one that exits).
  It holds off while OpenClaw waits on a stale lock.

Auth works the same as online: a single admin password (bcrypt) and 30-minute sessions.

## Deploy

GitLab CI (`.gitlab-ci.yml`) runs the tests and, on `main`, builds the image with
Kaniko and pushes `registry.bulka.in/cupatea/openclaw-panel/main:latest` (plus a
`main:<sha>` tag). `bin/build` is for local builds.

1. Put `../docker-compose.yaml` (which includes the `openclaw-panel` service) on the NAS.
2. Move the tokens into `.env` next to it: `OPENCLAW_GATEWAY_TOKEN=…` and `TELEGRAM_BOT_TOKEN=…`.
   The compose file leaves them empty, so compose reads them from `.env`.
3. Run `docker compose up -d openclaw-panel`, open `http://<nas>:3006`, and create the password.
   The registry is private, so the NAS needs `docker login registry.bulka.in` once (like for food).

The panel mounts the folder at `/openclaw` and finds its real host path from its
own container mounts. Override this with `OPENCLAW_HOST_DIR` if needed. Compose then runs
with `--project-directory <host path>`, so containers match what `docker compose up -d`
on the NAS would create.

**Security:** access to the Docker socket is root on the NAS. Keep the port (3006 on the NAS) on the tailnet.

Development: `bin/setup`, then `bin/dev` (it uses `..` as the OpenClaw folder). Tests: `bin/rails test`.
