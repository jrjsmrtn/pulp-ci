<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

Measured 2026-09-16, pulpcore 3.118.0, both architectures built natively:

| Arch | On disk | Compressed | Usable API | Host |
|---|---|---|---|---|
| arm64 | 333 MB | 102 MB | 6.8 s | Apple M5 |
| amd64 | 303 MB | not measured | 21.5 s | Intel Mac mini 2018, 4 vCPU |

Against `quay.io/pulp/pulp:latest` at 520 MB compressed / 1484 MB on disk (arm64), 538 MB
compressed (amd64). `pip freeze` is byte-identical across the two builds.
