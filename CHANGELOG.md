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

Measured 2026-09-16, arm64, pulpcore 3.118.0: **102 MB compressed / 333 MB on disk**,
**6.8 s** from container start to a usable API, against `quay.io/pulp/pulp:latest` at
520 MB compressed / 1484 MB on disk.
