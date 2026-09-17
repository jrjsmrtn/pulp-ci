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
- **PostgreSQL.** A CI service container, where the job can wipe it between runs. It
  cannot be replaced by SQLite to drop that service — see
  [SQLite is not an option](#sqlite-is-not-an-option) — and PGlite runs but does not
  behave like PostgreSQL — see [PGlite is not a substitute](#pglite-is-not-a-substitute).
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
| Run on SQLite, no database service | One container per CI job | pulpcore does not run on SQLite — see below | Not viable |
| Run on PGlite behind `pglite-socket` | Passes the smoke test; no PostgreSQL server | Still a separate database process; all connections share one session, so advisory locks do not exclude and one open transaction blocks every other connection — see below | Rejected |

### SQLite is not an option

Tested 2026-09-17 against this image, pulpcore 3.118.0. With the engine overridden to
`django.db.backends.sqlite3` (confirmed in effect via `pulpcore-manager shell`),
`pulpcore-manager migrate` applies migrations up to `core.0097` and then fails at
`core.0098_pulp_labels` with exit code 1:

```
ValueError: Cannot quote parameter value {} of type <class 'dict'>
```

That migration enables PostgreSQL's `hstore` extension and adds `HStoreField` columns,
neither of which SQLite has. It is not an isolated case. In the installed source:

- the default engine is `django.db.backends.postgresql` (`pulpcore/app/settings.py`);
- 23 non-test modules import `django.contrib.postgres`;
- migration `0134_task_insert_trigger` installs a trigger calling `pg_advisory_xact_lock`;
- nothing outside the tests mentions SQLite.

Getting past the migrations would not be enough either. The **No Redis** omission above
depends on workers coordinating through PostgreSQL advisory locks, so the task system
needs PostgreSQL too.

The only way to have one container per CI job is to embed PostgreSQL in the image. That
is the upstream shape this decision rejects on size. Only 3.118.0 was tested; the
migration history makes a change in a later release unlikely, but that is an inference.

### PGlite is not a substitute

Tested 2026-09-17 against this image, pulpcore 3.118.0. The database was PGlite 0.5.4
(PostgreSQL 18.3 compiled to WASM) with its `hstore` extension, served over the
PostgreSQL wire protocol by `pglite-socket` 0.2.7 with `maxConnections: 20`, running on
the host.

**It works as far as the smoke test reaches.** Every migration applied, including
`core.0098_pulp_labels` and `core.0134_task_insert_trigger`. A worker came online,
`bin/smoke-test.sh` exited 0, and the two tasks it dispatches (`ageneral_delete` and
`orphan_cleanup`) both reached `completed`.

**It does not behave like PostgreSQL once there is more than one connection.** PGlite is
a single-connection database. `pglite-socket` accepts many clients by multiplexing them
onto that one session, and its README warns that "not all use cases are guaranteed to
work". Probed from inside the Pulp container with two psycopg connections:

| Probe | PostgreSQL | PGlite via `pglite-socket` |
|---|---|---|
| `pg_backend_pid()` on two connections | Different | Both `42`: one shared session |
| B runs `pg_try_advisory_lock(42)` while A holds it | `false` | `true` |
| A query on another connection while a transaction is open | Answers at once | Blocked until that transaction ends (still blocked after 5 s) |

These break things Pulp depends on:

- **Advisory locks do not exclude.** Workers use them to claim tasks and to keep two
  tasks off the same resource. The smoke test never runs two tasks against each other,
  so passing it says nothing about this. A suite that does could see tasks corrupt each
  other and report it as a Pulp failure.
- **One open transaction stops every other connection.** Tasks run in transactions, so
  the API stops answering for as long as a task holds one. If code with a transaction
  open waits on a second connection, it hangs instead of failing.

Not tested: `LISTEN`/`NOTIFY`, which workers use to wake up, and PGlite's 32-bit WASM
memory limit under a real workload.

**It would not remove a service either.** Pulp still needs a database process beside it,
Node and WASM instead of `postgres:17-alpine`. The trade is a real server for one whose
results differ from production. The one case that might justify it is a runner that
cannot run containers at all, and no such runner is in scope.

## Outcome

Measured the same day the decision was taken, pulpcore 3.118.0, each architecture built
natively rather than emulated:

| | This image (arm64) | This image (amd64) | `quay.io/pulp/pulp` |
|---|---|---|---|
| Compressed (registry transfer) | **102 MB**, 11 layers | not measured | 520 MB arm64 / 538 MB amd64, 44 layers |
| Uncompressed (on disk) | **333 MB** | **303 MB** | 1484 MB (arm64) |
| Container start → usable API | **6.8 s** | **21.5 s** | not measured |

The start-up difference is the host, not the image — an M5 laptop against a 2018 Intel Mac
mini with 4 vCPUs. `pip freeze` is byte-identical across both builds, so the dependency
resolution does not vary by architecture; only wheels and base layers do.

"Usable API" is the criterion from ADR-0002, not an open port: 93 migrations applied to an
empty database, a worker online, and `POST /pulp/api/v3/repositories/file/file/` returning
a created repository.

### Addendum 2026-09-17: the runtime stage upgrades the Debian base

The first grype scan of this image, with a vulnerability database built that morning, found
21 High or Critical findings with a fix available. All 21 were Debian packages from
`python:3.13-slim` (`libc6`, `perl-base`, `libpcre2-8-0`, `libsqlite3-0`, `gzip`), although
the base had been pulled the same day. None were in pulpcore or its Python dependencies.
Debian had shipped the fixes; the base image had not yet been rebuilt with them.

The runtime stage now runs `apt-get upgrade` before copying the virtualenv. A probe build
with that layer had no fixable High/Critical findings left. CI fails on any new one, under
the policy in `.grype.yaml`.

The cost is size, because files replaced by the upgrade still sit in the base layer below.
Measured with `bin/measure.sh`, same pulpcore and an identical `pip freeze`:

| | arm64 | amd64 |
|---|---|---|
| Uncompressed (on disk), before | 333 MB, 11 layers | 303 MB, 11 layers |
| Uncompressed (on disk), after | **376 MB**, 12 layers | **335 MB**, 12 layers |
| Container start → usable API, after | 6.8 s | 21.3 s |

Compressed size was not re-measured. The trade stands against upstream: 376 MB on disk
against 1484 MB.

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
