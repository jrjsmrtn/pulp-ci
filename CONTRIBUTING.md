<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# Contributing to pulp-ci

pulp-ci builds a Pulp container image for one purpose: running integration tests against
the Pulp REST API in CI. Read [What is in it](README.md#what-is-in-it) and
[ADR-0003](docs/adr/0003-trimmed-pulp-image-on-python-slim.md) before proposing a change.
Most of what the image leaves out, it leaves out on purpose.

## What belongs here

This image is a **test fixture, not a deployment**. Changes that make it more
production-like will be declined:

- TLS, nginx, a process supervisor, an embedded database or Redis;
- plugins beyond what integration tests against the Pulp API need, because every plugin
  adds dependency weight;
- configurable credentials. The admin password and `SECRET_KEY` are constants on purpose,
  and that is only safe because the image never runs outside CI.

Changes that are welcome: a smaller or faster image, a readiness check that catches a
failure the current one misses, a fix for a breaking upstream Pulp change, and corrections
to anything the documentation claims.

**Bugs**: open an issue with the pulpcore version (`pip freeze` in the image, or the image
tag), the architecture, and the container log. **Features**: open an issue first and say
which integration test needs it.

## Development setup

You need:

| Tool | Used for |
|---|---|
| podman (or Docker) | building and running the image |
| [lefthook](https://github.com/evilmartians/lefthook) | the git hooks below |
| gitleaks, shellcheck, shfmt, yamllint, reuse | pre-commit gates |
| grype | the vulnerability gate, run locally |
| curl, python3 | `bin/measure.sh` and `bin/smoke-test.sh` |

Install the hooks once per clone:

```bash
lefthook install
```

Pre-commit runs gitleaks, shellcheck, shfmt, yamllint, `reuse lint`, and a check that every
workflow action is pinned to a commit SHA. The commit-msg hook checks the DCO sign-off
described below. No hook builds the image: that takes minutes, so it happens in the checks
you run yourself and in CI.

## Checking a change

The claims worth making about this image are measured ones.

```bash
bin/measure.sh                                       # build, size, time to a usable API
bin/smoke-test.sh http://localhost:24817 <password>  # drive the API against a running stack
podman save --format oci-archive -o /tmp/pulp-ci.tar localhost/pulp-ci:dev
grype oci-archive:/tmp/pulp-ci.tar                   # exit 2 = policy failed
```

`bin/measure.sh` builds the image, starts it against a throwaway PostgreSQL, and waits for
a usable API: the database connected and a worker online. **Do not quote a size or a
start-up time in a README, ADR or commit message unless `bin/measure.sh` printed it**, and
say whether a size is compressed or on disk. The two differ by roughly three times.

CI builds the image with `compose.ci.yml`, runs the smoke test, and fails on any High or
Critical vulnerability with a fix available (`.grype.yaml`).

## Branches, commits and changelog

- Gitflow-lite: branch from `develop`; `main` holds releases.
- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`,
  `ci:`, `chore:`.
- A commit message must not claim more than the commit contains.
- Add a line under `[Unreleased]` in `CHANGELOG.md` for anything a user of the image would
  notice.
- New files need SPDX headers. `reuse lint` must pass.

## Contribution terms

### Developer Certificate of Origin

pulp-ci uses the **[Developer Certificate of Origin](https://developercertificate.org/)
(DCO) 1.1**. There is no CLA to sign. You certify the DCO by signing off each commit:

```bash
git commit -s -m "your message"
```

which adds a trailer with the name and email from your git configuration:

```text
Signed-off-by: Jane Developer <jane@example.com>
```

Use a real name and a reachable email. The sign-off is a statement that you have the right
to submit the work, and it stays in the public history permanently. It must match the
commit's author email; CI checks every commit in a pull request.

**Only the human contributor may add it.** Not a script, not an AI agent, not a tool that
amends a commit after a hook failed. A tool that needs a sign-off must hand the work back
unsigned.

Forgot it? Fix the last commit with `git commit -s --amend --no-edit`, or a whole branch
with `git rebase --signoff develop`, then force-push your branch.

What you certify, verbatim:

<!-- REUSE-IgnoreStart -->

```text
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

<!-- REUSE-IgnoreEnd -->

(a), (b) and (c) are **alternatives**: you need to meet only one. What matters is the
right to submit, not sole authorship. Contributions are licensed under the
[Apache License 2.0](LICENSE).

### AI-assisted contributions

**Permitted.** You may use AI tools to help write code, documentation or commit messages,
and no disclosure is required.

You remain the contributor. Your sign-off covers AI-assisted work exactly as it covers
anything else you submit, so do not sign off on output you have not read, cannot explain,
or whose origin you cannot account for.

The decision behind these terms is recorded in
[ADR-0004](docs/adr/0004-open-the-source-keep-the-image-internal.md).
