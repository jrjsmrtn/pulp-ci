<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# 3. Build a Trimmed Pulp Image on python-slim for CI

Date: 2026-09-16

## Status

Accepted

## Context

CI jobs need a Pulp instance to run integration tests against its REST API. The obvious
choice is the image upstream publishes, `quay.io/pulp/pulp`.

Measured 2026-09-16 on arm64: **520 MB compressed** across 44 layers — what a CI job
actually transfers — and **1484 MB uncompressed** once unpacked. (amd64 compressed:
538 MB.) It is a complete single-host deployment — it embeds PostgreSQL and Redis,
runs nginx in front of the API and content apps, and supervises the lot with s6.

In CI none of that is wanted. The database belongs in a service container so the job
controls its lifecycle; nothing browses a web UI; and a supervisor actively hurts, because
it restarts a dead worker and keeps the API answering 200 while tasks silently stop being
processed.

## Decision

Build our own image for this one purpose, from `docker.io/library/python:3.13-slim`, in
two stages: compilers in the build stage, a copied virtualenv in the runtime stage.

**Contents**: `pulpcore`, `pulp-file`, and nothing else. Three processes started by a shell
entrypoint — `pulpcore-api`, `pulpcore-content`, `pulpcore-worker`.

**Explicit omissions**, each with its reason:

- **Redis.** `WORKER_TYPE = "pulpcore"` coordinates workers through PostgreSQL advisory
  locks, and `CACHE_ENABLED = False` removes the only other consumer. Redis is therefore
  not an optional dependency that we skipped — with those two settings it is not a
  dependency at all. This halves the service count in every CI job.
- **nginx / `pulp-web`.** Upstream's proxy exists to merge the API and content apps onto a
  single port. A test client can address two ports.
- **PostgreSQL.** A CI service container, where the job can wipe it between runs.
- **s6 or any supervisor.** The entrypoint uses `wait -n` and a trap: when any of the three
  processes dies the container exits, and CI reports a crash instead of a hang. This is a
  feature specific to being a test fixture and would be wrong in production.

**Why `python:*-slim` and not UBI**, which is what upstream builds on: `pulpcore` pulls
`psycopg[binary]`, which vendors its own libpq. Without that, a slim Debian base would need
PostgreSQL client libraries installed, and the UBI base would win on convenience.

**Publication**: the built image goes to an internal, authenticated OCI registry and
nowhere else; its address is a local detail, kept in `CLAUDE.local.md` rather than here. It is never pushed to a public registry — it ships a fixed, deliberately
insecure `SECRET_KEY` and a constant admin password, which are safe only under that
assumption.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| `quay.io/pulp/pulp` | Zero work; upstream-supported | 520 MB compressed / 1484 MB unpacked; embeds PostgreSQL and Redis; s6 masks dead workers | Rejected |
| `pulp-minimal` + `pulp-web` | Upstream-supported; closer to a real split deployment | Two images and a proxy to orchestrate for no test-visible benefit | Rejected |
| Install pulpcore on the runner directly (no container) | Smallest possible footprint | Runner-state dependent; not reproducible; pollutes the runner | Rejected |
| Build a purpose-made image (**chosen**) | Only what the tests need; no Redis; crash-fast | Ours to maintain; drifts from upstream packaging | **Selected** |

## Outcome

Measured the same day the decision was taken, arm64, pulpcore 3.118.0:

| | This image | `quay.io/pulp/pulp` |
|---|---|---|
| Compressed (registry transfer) | **102 MB**, 11 layers | 520 MB, 44 layers |
| Uncompressed (on disk) | **333 MB** | 1484 MB |
| Container start → usable API | **6.8 s** | not measured |

"Usable API" is the criterion from ADR-0002, not an open port: 93 migrations applied to an
empty database, a worker online, and `POST /pulp/api/v3/repositories/file/file/` returning
a created repository.

## Consequences

**Positive**: fewer services per CI job, roughly a fifth of the bytes to pull, and a
container that fails loudly instead of hanging.

**Negative**: we now maintain a Pulp packaging, and upstream changes (a renamed entry
point, a new mandatory setting) will break it at some point. The mitigation is that
`bin/measure.sh` proves the whole thing end to end in one command, so the breakage surfaces
as a failed measurement rather than as a mysterious CI timeout.

**Risk**: dependencies are installed unpinned and the resolved set is recorded at build
time (`/opt/venv/requirements.lock`, extracted to `measurements/`). That favours catching
upstream drift early over reproducibility. If a green build later needs to be reproduced
exactly, pin from a recorded lock file.

## References

- [pulp-oci-images](https://github.com/pulp/pulp-oci-images) — upstream's Containerfiles
- [Pulp installation settings](https://pulpproject.org/pulpcore/docs/admin/reference/settings/)
