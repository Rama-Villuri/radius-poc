# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A POC for RADIUS-based SSH authentication across two local devices:
- **Mac Mini M2** — runs FreeRADIUS in Docker (the authentication server)
- **Raspberry Pi (Ubuntu, hostname `homeserver`)** — SSH target; delegates password auth to RADIUS via PAM

RADIUS only handles password verification. The Pi still requires a local account (`useradd`) for each RADIUS user — Linux needs a local `/etc/passwd` entry for the shell, UID, home directory, and PAM session/account phases.

## Infrastructure

| Component | Location | IP |
|---|---|---|
| FreeRADIUS (Docker) | Mac Mini | 192.168.0.132 |
| Raspberry Pi (SSH target) | Pi | 192.168.0.119 |

Shared secret between Pi PAM client and FreeRADIUS: `radius-shared-secret`

## Running the RADIUS server (Mac Mini)

```bash
cd docker
docker compose up -d          # start
docker compose down           # stop (use down, not stop — mounts only apply on recreate)
docker logs -f freeradius     # watch debug output (runs with -X flag)
```

**Important:** Always use `docker compose down && docker compose up -d` when changing `docker-compose.yml` or config files. `docker compose restart` does not recreate the container and will not pick up volume mount changes.

## Testing RADIUS auth (Mac Mini)

Requires `radtest`: `brew install freeradius-server`

```bash
# Quick manual test against localhost
docker exec freeradius radtest radius-testuser TestPass123! localhost 0 testing123

# Full test suite
bash test/test-radius.sh
```

## Adding a RADIUS user

1. Add an entry to [docker/freeradius/users](docker/freeradius/users):
   ```
   newuser   Cleartext-Password := "somepassword"
       Reply-Message = "RADIUS auth OK for %{User-Name}"
   ```
2. Recreate the container: `docker compose down && docker compose up -d`
3. On the Pi, create a matching local account (no password — RADIUS is the only auth path):
   ```bash
   sudo useradd -m -s /bin/bash newuser
   ```

## Raspberry Pi setup

`raspi-setup/setup.sh` configures the Pi. Edit `MAC_MINI_IP` and `SHARED_SECRET` at the top before running. It:
- Installs `libpam-radius-auth` and `freeradius-utils`
- Writes `/etc/pam_radius_auth.conf` (backed up if existing)
- Prepends `auth sufficient pam_radius_auth.so` to `/etc/pam.d/sshd` (backed up)
- Verifies `UsePAM yes`, `KbdInteractiveAuthentication yes`, `PasswordAuthentication yes` in sshd_config
- Creates local accounts for each user in `RADIUS_USERS`

Rollback: `sudo cp /etc/pam.d/sshd.bak /etc/pam.d/sshd && sudo systemctl restart sshd`

## How auth works end-to-end

```
ssh radius-testuser@pi
  → sshd → PAM → pam_radius_auth.so
                   → UDP 1812 → FreeRADIUS (Mac Mini Docker)
                              ← Access-Accept
  ← SSH session opened
```

PAM uses `sufficient` for `pam_radius_auth.so` — if RADIUS fails or is unreachable, it falls through to `pam_unix` (local password). Existing users and key-based auth are unaffected.

## Docker networking note

Docker Desktop on Mac NATs incoming UDP through its internal bridge (`172.24.x.x`). FreeRADIUS therefore sees requests from `172.24.0.1` rather than the Pi's real IP. The `docker-mac` client block in `clients.conf` (covering `172.16.0.0/12`) handles this.

## Debugging

On Pi: `sudo tail -f /var/log/auth.log` — shows PAM module invocations and SSH accept/reject.

"Invalid user X" in auth.log means the local account doesn't exist yet — `sudo useradd -m -s /bin/bash X`.

On Mac Mini: `docker logs freeradius` shows every Access-Request/Accept/Reject when running in `-X` (debug) mode.
