<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# Security Policy

pulp-ci has **one maintainer**, working on it in their own time. There is no security team,
no on-call rota and no backup if that person is away. This policy promises only what one
person can keep.

pulp-ci is **not part of the Pulp Project** and is not affiliated with it or with Red Hat.

## What to report where

| The problem is in… | Report it to |
|---|---|
| pulpcore, pulp-file, or another Pulp plugin | **Pulp**, not here: <pulp-security@redhat.com>, per [Pulp's security policy](https://github.com/pulp/governance) |
| Debian or Python packages in the `python:*-slim` base | Their upstream. If CI's grype scan passes while a **fixable** High or Critical finding is present, report that here. |
| This repository: the `Containerfile`, entrypoint, settings, scripts or CI workflow | **Here**, as below |

## Known and intended: not vulnerabilities

The image is a CI test fixture and is **insecure by design**. None of the following needs
reporting:

- the fixed `SECRET_KEY` and constant admin password;
- `ALLOWED_HOSTS = ["*"]`, no TLS, and the API served without a reverse proxy;
- the database encryption key being generated at build time, so everyone running the same
  image shares it.

They are safe only because the image is meant to run inside a CI job and be thrown away.
Running it anywhere reachable is outside what this project supports; see the warning in the
[README](README.md).

## What is worth reporting

- A way the image or its build **reaches beyond the CI job**: exposing the runner's secrets
  or tokens, writing outside its own volumes, or making network calls it has no reason to
  make.
- A flaw in the **CI workflow**: script injection from pull-request content, excessive token
  permissions, or a way to skip the DCO or vulnerability checks.
- A **supply-chain** weakness: a way to substitute the base image, a Python dependency, or
  the grype binary that the signature and checksum checks would not catch.

## How to report

Report privately. **Do not open a public issue or pull request.**

- **Email**: <jrjsmrtn@gmail.com>, with "pulp-ci security" in the subject.
- **GitHub**: once the repository is public, "Report a vulnerability" on the Security tab
  (private vulnerability reporting) works too, and is preferred.

Include what you found, how to reproduce it, and what you think its impact is.

## What to expect

- **Acknowledgement**: I aim to reply within **7 days**. This is best effort, not a
  guarantee.
- **No reply after 14 days**: send a follow-up. The message may simply have been missed.
- **Fix**: on `develop` and in the next patch release. Only the **latest release** is
  supported; older tags are not patched.
- **Disclosure**: coordinated. I ask for up to **90 days** from your report before public
  disclosure, or less once a fix is released. If you have had **no acknowledgement after
  30 days**, you may disclose.
- **Credit**: in the release notes and any advisory, unless you prefer not to be named.

There is no bug bounty.

## Supported versions

| Version | Supported |
|---|---|
| Latest 0.1.x release | Yes |
| Older tags | No |
