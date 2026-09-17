<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# pulp-ci

A [Pulp](https://pulpproject.org) container image for running integration tests against the
Pulp REST API in CI — and for nothing else.

> **Not for production, and not safe outside CI.** This image ships a fixed
> `SECRET_KEY`, a constant admin password, `ALLOWED_HOSTS = ["*"]`, and no TLS. Those are
> deliberate: it exists to be created and destroyed by a CI job. Do not run it anywhere
> reachable.

## Why not `quay.io/pulp/pulp`

Upstream's image is a complete single-host deployment: it embeds PostgreSQL and Redis, runs
nginx, and supervises everything with s6. In CI the database wants to be a service
container the job controls, nothing browses a web UI, and a supervisor is actively harmful
— it restarts a dead worker while the API keeps answering `200`, so a broken run looks like
a hung one.

Measured 2026-09-16 on arm64 (Apple M5), pulpcore 3.118.0:

| | This image | `quay.io/pulp/pulp:latest` |
|---|---|---|
| Compressed — what CI pulls | **102 MB** (11 layers) | 520 MB (44 layers) |
| Uncompressed — on disk | **333 MB** | 1484 MB |
| Container start → usable API | **6.8 s** | not measured |

Built and measured on amd64 too, natively on an Intel Mac the same day: **303 MB on disk**,
11 layers, usable API in **21.5 s** — against upstream's 538 MB compressed for that
architecture. The dependency set resolves byte-identically on both (`pip freeze` output
matches exactly), so the two builds differ only in wheels and base layers.

The start-up gap is the host, not the image: 6.8 s on an M5 laptop versus 21.5 s on a 2018
Intel Mac mini with 4 vCPUs. Quote whichever matches the CI runner you are sizing for.
Compressed size was measured only on arm64.

"Usable API" is a deliberately strict definition — see [Readiness](#readiness).

## What is in it

`pulpcore` and `pulp-file`, in a virtualenv on `python:3.13-slim`, running three processes
under a shell entrypoint: `pulpcore-api` (:24817), `pulpcore-content` (:24816) and
`pulpcore-worker`.

**No Redis.** `WORKER_TYPE = "pulpcore"` coordinates workers through PostgreSQL advisory
locks and `CACHE_ENABLED = False` removes the only other consumer, so Redis is not a
dependency at all — not merely one we skipped. That halves the service count in a CI job.

**No nginx, no embedded database, no supervisor.** See
[ADR-0003](docs/adr/0003-trimmed-pulp-image-on-python-slim.md) for each omission and its
reason.

## Use it

```bash
podman build --tag pulp-ci:dev --file Containerfile .
podman compose --file compose.ci.yml up
```

`compose.ci.yml` is the shape a CI job should copy: one PostgreSQL service (on tmpfs — the
data dies with the job) and this image. The API is then at `http://localhost:24817`, with
`admin` and whatever `PULP_ADMIN_PASSWORD` you set.

| Variable | Default | Purpose |
|---|---|---|
| `POSTGRES_HOST` / `POSTGRES_PORT` | `127.0.0.1` / `5432` | Where the database is |
| `POSTGRES_DB` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | `pulp` | Database credentials |
| `PULP_ADMIN_PASSWORD` | `password` | Set on every start |
| `PULP_CONTENT_ORIGIN` | `http://localhost:24816` | Must be reachable by the test client |

The entrypoint waits for PostgreSQL, runs `migrate`, sets the admin password, then starts
the three processes. If any one of them exits, the container exits — so CI reports a crash
rather than timing out.

## Readiness

Wait for this, not for the port to open:

```
GET /pulp/api/v3/status/ → 200
  AND database_connection.connected is true
  AND online_workers is non-empty
```

A Pulp whose database is unreachable, or whose worker is dead, still answers on the port
and can still return `200`. Waiting on anything weaker is how an integration suite ends up
hanging until its own timeout with nothing useful in the log. `compose.ci.yml`'s healthcheck
and `bin/measure.sh` both use exactly this criterion.

## CI

`.github/workflows/ci.yml` builds the image, brings the stack up with
`docker compose -f compose.ci.yml up --build --wait`, and runs `bin/smoke-test.sh`.

`--wait` is the whole readiness gate: it blocks until every healthcheck passes and fails the
job if one never does, so there are no sleeps and no polling loops in the workflow. The
criterion it waits for is the one above, encoded in the compose healthcheck.

The smoke test goes further than "the API answered" — it asserts the status contract, then
creates a file repository, reads it back and deletes it. A POST that returns a href while
leaving nothing behind would pass a weaker check.

Run the same thing locally against a stack you started by hand:

```bash
bin/smoke-test.sh http://localhost:24817 password
```

**CI does not publish the image.** It is pushed by hand to an internal registry that a
hosted runner cannot reach.

### Consuming it from another project

Copy the two services out of `compose.ci.yml`, or run the published image directly with a
PostgreSQL service container — the only settings that matter are `POSTGRES_*`,
`PULP_ADMIN_PASSWORD` and a `PULP_CONTENT_ORIGIN` the test client can actually reach.

## Measure it

```bash
bin/measure.sh
```

Builds the image, records its size, starts it against a throwaway PostgreSQL, times how
long until the API is *usable* by the definition above, and writes a JSON record plus the
resolved dependency set into `measurements/`.

Every number in this README came from that script or from a registry manifest, on the date
given. Do not quote a figure it did not produce — sizes and start-up times move with every
dependency bump, and a stale number reads as a current one.

## License

Apache-2.0 — see [LICENSE](LICENSE). This repository is
[REUSE](https://reuse.software/)-compliant.

The **built image** is a different matter: it is a mixed-license aggregate bundling
pulpcore (GPL-2.0-or-later) and its dependency tree. It is published only to an internal
registry. Publishing it anywhere public would require a copyleft-floor analysis first — see
[ADR-0002](docs/adr/0002-adopt-development-best-practices.md).
