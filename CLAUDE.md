<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Context

- **Category**: Development
- **Type**: container image / CI tooling
- **Stack**: Containerfile, podman, Python (pulpcore)
- **License**: Apache-2.0
- **Tier**: t1
- **Distribution profile**: Public source, private image (ADR-0004). The repository is
  public on GitHub since 2026-09-17. The image ships to an internal OCI registry only, never
  a public one; the registry's address is in `CLAUDE.local.md`. Consumers build from source.
- **Contribution terms**: DCO 1.1, enforced. Every commit needs a human `Signed-off-by:`,
  so an assistant stages its work and hands the commit back unsigned.

## Project Tier

Current tier: **t1**.

Tier artifacts present: `CLAUDE.md`, conventional commits, `CHANGELOG.md`, `README.md`,
foundation ADRs in `docs/adr/`, lefthook gates.

Promotion trigger being watched: t1 → t2 if this grows past one image and its harness — a
Diátaxis tree and a C4 model would then earn their keep. One Containerfile does not.

## What this is

A Pulp container image built for **integration testing against the Pulp REST API in CI**,
and for nothing else. The upstream `quay.io/pulp/pulp` image is a full single-container
deployment: it embeds PostgreSQL and Redis, runs nginx, and is supervised by s6. All of
that is dead weight in CI, where the database is a service container and nothing browses
the web UI.

Measured baseline, `quay.io/pulp/pulp:latest`, 2026-09-16, arm64: **520 MB compressed**
(the registry transfer, 44 layers) and **1484 MB uncompressed** (on disk after pulling).
amd64 compressed is 538 MB.

**Always say which of the two a number is.** They differ by nearly 3×, and quoting one
under the other's name is the single easiest way to make this project look pointless or
miraculous. `bin/measure.sh` records the uncompressed figure, because that is what
`podman image inspect` reports; the compressed figure comes from the registry manifest.

## Scope discipline

This image is a **test fixture**, not a deployment. Things that do not belong here:

- Anything that makes it more production-like — TLS, nginx, a supervisor, embedded
  databases, health endpoints beyond what the tests actually call.
- Plugins beyond what the tests under test require. Every plugin is dependency weight.
- Any credential that is not obviously and deliberately insecure. This image exists to be
  thrown away; its admin password is a constant on purpose, and that is only safe because
  the image must never run anywhere but CI. **Do not make it configurable and then rely on
  that** — see the warning in `README.md`.

## Design decisions already made

Each of these is a size or start-up decision, recorded so it is not relitigated:

- **No Redis.** `WORKER_TYPE = "pulpcore"` makes pulpcore use PostgreSQL advisory locks
  rather than Redis for worker coordination, and `CACHE_ENABLED = False` removes the only
  other use. Redis is therefore not a dependency at all, not merely an optional one.
- **No nginx / no `pulp-web`.** `pulpcore-api` (gunicorn) and `pulpcore-content` serve the
  API and content directly. The reverse proxy exists upstream to merge them onto one port;
  a test client can address two ports.
- **PostgreSQL is a CI service container**, not part of the image.
- **`python:*-slim` base, not UBI.** `psycopg[binary]` ships its own libpq, which is what
  makes a slim Debian base viable without installing PostgreSQL client libraries.

## Verifying a change

The only claims worth making about this image are measured ones. `bin/measure.sh` builds
it, records the size, starts it against a throwaway PostgreSQL, and times the wait until
`/pulp/api/v3/status/` first answers `200`.

```bash
bin/measure.sh
```

**Do not quote a size or a start-up time that this script did not print.** Both change
with every dependency bump, and a stale number in the README is worse than none because it
reads as current.
