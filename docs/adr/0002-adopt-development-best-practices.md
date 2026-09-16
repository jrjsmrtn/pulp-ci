<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# 2. Adopt Development Best Practices

Date: 2026-09-16

## Status

Accepted

## Context

pulp-ci is a tier-t1 project: a container image and a harness, maintained by one person,
private, and rebuilt rather than released. The practices below are scaled to that. Several
sections that the house template carries — Diátaxis documentation trees, C4 models, sprint
cadence, BDD — are deliberately not adopted, because this project has one deliverable and
no user interface to describe.

## Decision

### Testing

There is no unit-test suite, and adding one would be theatre: the deliverable is an image,
and the only meaningful assertion about it is that it serves a working API. That assertion
lives in `bin/measure.sh`, which is the test suite.

Its readiness criterion is chosen with care and is the one thing here worth defending. It
is **not** "the port is open" or "HTTP returned 200" — both are true of a Pulp whose
database is unreachable or whose worker is dead, which is precisely the state that makes an
integration suite hang until its own timeout with no useful diagnosis. The criterion is:

> `/pulp/api/v3/status/` returns 200, `database_connection.connected` is true, **and**
> `online_workers` is non-empty.

`compose.ci.yml` repeats the same criterion as its healthcheck, so CI and the local
measurement agree on what "up" means.

### Versioning

Semantic versioning, patch-level during development (0.1.x). The image is tagged with the
resolved `pulpcore` version rather than the project version, because what a consumer cares
about is which Pulp they are testing against.

### Git workflow

Gitflow-lite: `main` for releases, `develop` for integration, `feature/*` branches.
Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`).

A commit message must not claim more than the commit contains — the relevant failure here
is a message describing a Containerfile change that the build never exercised. Re-read the
message against `git diff --cached`, not against the intent.

### Changelog

Keep a Changelog format in `CHANGELOG.md`.

### Formatting and quality gates

`.editorconfig` for whitespace; `shfmt` and `shellcheck` for the shell scripts, which are
where the real logic lives. Enforced by lefthook on pre-commit, together with `gitleaks`
and `reuse lint`.

**No gate builds the image.** A build takes minutes and needs a running podman machine;
putting it on pre-commit would guarantee it gets bypassed with `--no-verify`, which costs
more than it buys. The build is verified by running `bin/measure.sh` and in CI.

### Licensing

Apache-2.0, REUSE-compliant: SPDX headers on every file, license texts in `LICENSES/`,
bulk annotations in `REUSE.toml`, `reuse lint` on pre-commit.

Note that the **shipped image** is a mixed-license aggregate — it bundles pulpcore
(GPL-2.0-or-later) and its dependency tree. This repository's Apache-2.0 license covers
this repository's files only. The image is not redistributed publicly (see ADR-0003), so
the obligations that would attach to redistribution are not currently triggered; if that
changes, the aggregate needs a `LICENSING.md` and a copyleft-floor analysis before it is
published anywhere public.

### Measurement discipline

Any size or timing figure that appears in the README or a commit message must come from a
`bin/measure.sh` run, and be dated. Both change with every dependency bump, and a stale
number reads as a current one.

## Consequences

**Positive**: the gates are all fast and none of them is tempting to skip. The one
expensive check is the one that actually proves the artifact works.

**Negative**: no unit tests means a broken `measure.sh` is only discovered when it is run.
Accepted — it is 150 lines and running it is the normal workflow.

## References

- [AI-Assisted Project Orchestration](https://github.com/jrjsmrtn/ai-assisted-project-orchestration)
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), [SemVer](https://semver.org/)
- [REUSE](https://reuse.software/)
