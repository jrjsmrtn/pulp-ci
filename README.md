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

Measured 2026-09-17 on arm64 (Apple M5), pulpcore 3.118.0, `bin/measure.sh`:

| | This image | `quay.io/pulp/pulp:latest` |
|---|---|---|
| Compressed — what CI pulls | **113 MB** (12 layers) | 520 MB (44 layers) |
| Uncompressed — on disk | **376 MB** (12 layers) | 1484 MB |
| Container start → usable API | **6.8 s** | not measured |

Built and measured on amd64 too, natively on an Intel Mac the same day: **335 MB on disk**,
12 layers, **111 MB compressed**, usable API in **21.3 s** — against upstream's 538 MB
compressed for that architecture. The dependency set resolves byte-identically on both (`pip freeze` output
matches exactly), so the two builds differ only in wheels and base layers.

The start-up gap is the host, not the image: 6.8 s on an M5 laptop versus 21.3 s on a 2018
Intel Mac mini with 4 vCPUs. Quote whichever matches the CI runner you are sizing for.

The 12th layer is an `apt-get upgrade` of the Debian base, added for the vulnerability scan
(see [Vulnerability scanning](#vulnerability-scanning)); it added 43 MB on arm64 and 32 MB
on amd64 on disk, and 11 MB to the compressed transfer on arm64 (102 MB before it).

Compressed sizes are the sum of the layer sizes in the manifests of the `v0.1.1` images
in the maintainer's private registry, read 2026-09-17. `bin/measure.sh` does not report them, because
podman only reports the uncompressed size.

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

**The image is not published to any public registry**, by CI or otherwise
([ADR-0003](docs/adr/0003-trimmed-pulp-image-on-python-slim.md),
[ADR-0004](docs/adr/0004-open-the-source-keep-the-image-internal.md)). It ships a fixed
`SECRET_KEY` and a constant admin password, and it bundles GPL-licensed pulpcore, which
would need its own licensing analysis before redistribution. Build it from this repository.

### Vulnerability scanning

CI scans the built image with [grype](https://github.com/anchore/grype) and **fails on any
High or Critical finding that has a fix available**. Findings with no fix (`wont-fix`,
`not-fixed`, `unknown`) are reported but never fail the build: nothing in this repository
could act on them. The policy is `.grype.yaml`, which grype reads from the repository root,
so a local run applies the same gate:

```bash
podman save --format oci-archive -o /tmp/pulp-ci.tar localhost/pulp-ci:dev
grype oci-archive:/tmp/pulp-ci.tar   # exit 2 = policy failed, 1 = grype error
```

The runtime stage runs `apt-get upgrade` because `python:*-slim` lags Debian's security
fixes. The first scan, on 2026-09-17, found 21 fixable High/Critical findings in the base
image and none in Pulp's Python dependencies; the upgrade cleared all 21.

### Consuming it from another project

No prebuilt image is published, so a consumer builds it from a **release tag** of this
repository, never a branch. There are two ways to do that.

**Build in the test job.** Copy the two services out of `compose.ci.yml`, which builds the
image from the `Containerfile`. Nothing else is needed, but every run pays for the image
build.

**Build once per release, into your own registry.** Better when many jobs use the image:

```bash
git clone --depth 1 --branch v0.1.1 https://github.com/jrjsmrtn/pulp-ci.git
cd pulp-ci
rev=$(git rev-parse HEAD)
podman build --pull=always \
  --label org.opencontainers.image.revision="$rev" \
  --label org.opencontainers.image.version=0.1.1 \
  --tag registry.example.com/ci/pulp-ci:0.1.1 --file Containerfile .
# run bin/smoke-test.sh and the grype scan (below) against it, then:
podman push registry.example.com/ci/pulp-ci:0.1.1
```

Then point the test job's `image:` at that tag instead of `build:`. For both amd64 and
arm64 runners, build each architecture and combine them into a manifest list; building
natively is much faster than emulation.

Either way, the only settings that matter are `POSTGRES_*`, `PULP_ADMIN_PASSWORD` and a
`PULP_CONTENT_ORIGIN` the test client can actually reach. Keep the image in a registry
that only your CI can read: it carries a fixed `SECRET_KEY` and a constant admin password.

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

## Contributing and security

Contributions are welcome under the Developer Certificate of Origin; see
[CONTRIBUTING.md](CONTRIBUTING.md), which also explains what does and does not belong in a
test fixture. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
This project has a single maintainer, and both documents are written to match that.
Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

pulp-ci is not part of the Pulp Project and is not affiliated with it or with Red Hat.

## License

Apache-2.0 — see [LICENSE](LICENSE). This repository is
[REUSE](https://reuse.software/)-compliant.

The **built image** is a different matter: it is a mixed-license aggregate bundling
pulpcore (GPL-2.0-or-later) and its dependency tree. It is not published to any public
registry; the maintainer's builds go to a private one. Publishing it anywhere public would
require a copyleft-floor analysis first — see
[ADR-0002](docs/adr/0002-adopt-development-best-practices.md).
