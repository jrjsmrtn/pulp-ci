<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The README and ADR-0003 give the compressed size on Python 3.14, read from the `v0.1.2`
  registry manifests: 114.4 MB (arm64) and 112.5 MB (amd64).

## [0.1.2] - 2026-09-17

### Added

- `CONTRIBUTING.md`: scope, development setup, how to check a change, and the contribution
  terms. Contributions are under the Developer Certificate of Origin 1.1, and AI-assisted
  contributions are permitted with no disclosure rule (ADR-0004).
- DCO enforcement: a lefthook `commit-msg` hook rejects commits without a `Signed-off-by:`
  trailer, and a CI job runs `bin/check-dco.sh` on every commit in a pull request.
- ADR-0004 (Proposed): if the repository goes public, only the source does; the image stays
  internal.
- `SECURITY.md` and `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), written for a single
  maintainer. Vulnerabilities in pulpcore itself are directed to the Pulp Project.
- Issue forms for bugs and features, a PR template, and `.github/release.yml`.
- A weekly scheduled CI run, so a newly published vulnerability or a new pulpcore release
  is noticed without waiting for a commit.
- Dependabot `docker` updates for the base image, each checked by CI before merge.
- CodeQL (Actions and Python), dependency review, and OpenSSF Scorecard workflows. Each runs
  only when the repository is public, so they switch on when it is made public.

### Changed

- The base image moves from Python 3.13 to 3.14 (`python:3.14-slim`, digest-pinned; PR #2,
  proposed by Dependabot). Measured with `bin/measure.sh`: on disk 376 → 382 MB on arm64
  and 335 → 340 MB on amd64, start-up 7.1 s and 22.0 s, and an identical `pip freeze`.
- The `python:3.13-slim` base is pinned by the digest of its multi-arch OCI index
  (`sha256:9d2e5553…`), in both stages, instead of a tag that upstream can move. It is the
  base `v0.1.1` was built on, so the image content does not change. A pre-commit gate
  rejects any `FROM` without a full digest.
- The README no longer assumes the private registry: consumers build the image from a
  release tag of this repository, either in the test job or once per release into their own
  registry.
- ADR-0004 records that no image is published to GHCR, public or private, and why.
- ADR-0002 no longer describes the project as private and unreleased.
- The repository is public (2026-09-17). ADR-0004 is Accepted, `CLAUDE.md` describes the
  public-source, private-image profile, and the README carries an OpenSSF Scorecard badge.

## [0.1.1] - 2026-09-17

### Changed

- `actions/checkout` is pinned to a commit SHA instead of a movable tag, and a pre-commit
  gate rejects any workflow action referenced by tag or branch.
- `actions/checkout` updated from v4.4.0 to v7.0.1 (#1, Dependabot). The majors crossed
  require Node 24 (v5), store credentials in a separate file (v6) and refuse fork checkouts
  under `pull_request_target`/`workflow_run` (v7); none applies to this workflow, which
  passes no inputs and uses neither trigger.
- The runtime stage runs `apt-get upgrade`, clearing 21 fixable High/Critical findings in
  the `python:3.13-slim` base. On disk the image grows from 333 to 376 MB on arm64 and from
  303 to 335 MB on amd64 (12 layers). Start-up measured 6.8 s and 21.3 s, against 6.8 s
  and 21.5 s before.

### Added

- Dependabot version updates for GitHub Actions: weekly, grouped into one PR, targeting
  `develop`.
- A grype scan in CI that fails on High/Critical findings with a fix available. The policy
  is `.grype.yaml`, shared by CI and local runs. grype v0.118.0 is installed only after
  `cosign verify-blob` proves its checksums file was signed by grype's own release workflow,
  and `sha256sum` ties the downloaded binary to that file.

## [0.1.0] - 2026-09-17

### Added

- Project bootstrap at tier t1: `CLAUDE.md`, `README.md`, foundation ADRs, Apache-2.0
  licensing with REUSE annotations, lefthook gates.
- A trimmed Pulp image for CI integration testing: `pulpcore` + `pulp-file` on
  `python:3.13-slim`, no Redis, no nginx, no embedded database, no supervisor.
- `bin/measure.sh`, which builds the image and proves it serves a usable API, and
  `compose.ci.yml` as the CI-facing shape.
- A GitHub Actions workflow that builds the image, waits on the compose healthchecks
  (`up --wait`, so no sleeps) and runs the new `bin/smoke-test.sh` — which asserts the
  status contract, then creates a file repository, reads it back and deletes it.
- `.yamllint.yml` and a yamllint pre-commit gate, now that the repository carries YAML
  worth linting.
- ADR-0003 records, from tests run against this image, why neither SQLite nor PGlite can
  replace the PostgreSQL service container.

Measured 2026-09-16, pulpcore 3.118.0, both architectures built natively:

| Arch | On disk | Compressed | Usable API | Host |
|---|---|---|---|---|
| arm64 | 333 MB | 102 MB | 6.8 s | Apple M5 |
| amd64 | 303 MB | not measured | 21.5 s | Intel Mac mini 2018, 4 vCPU |

Against `quay.io/pulp/pulp:latest` at 520 MB compressed / 1484 MB on disk (arm64), 538 MB
compressed (amd64). `pip freeze` is byte-identical across the two builds.
