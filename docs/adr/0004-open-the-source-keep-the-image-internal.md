<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# 4. Open the Source, Keep the Image Internal

Date: 2026-09-17

## Status

Proposed

The contribution terms below are decided and take effect now. Making the repository public
is not decided, and this record becomes Accepted only when that happens.

## Context

`CLAUDE.md` sets a **Private** distribution profile: the image goes to an internal registry
only, never a public one. ADR-0002 scales its practices to a private project, and ADR-0003
forbids publishing the image.

Two separate things could become public, and they carry different risks:

- **The source repository** is Apache-2.0 and passes `reuse lint`. A gitleaks scan of the
  full history with the homelab ruleset found no leaks, and a search of every blob for
  homelab host names, internal addresses and local paths found none (2026-09-17, 15
  commits). A consumer can build the image from it, because `compose.ci.yml` builds from
  the `Containerfile`.
- **The built image** ships a fixed `SECRET_KEY` and a constant admin password, and bundles
  pulpcore, which is GPL-2.0-or-later. ADR-0002 and ADR-0003 require a copyleft analysis
  and a `LICENSING.md` before it is redistributed.

Upstream does not already fill this role. `pulp/pulp-oci-images` has a `pulp_ci_centos`
image, but it embeds PostgreSQL, nginx and valkey under s6, which is the design ADR-0003
rejects.

Once outside contributions arrive, the terms they arrive under cannot be changed without the
agreement of every contributor. Those terms must be settled before the first one.

## Decision

**If the repository goes public, only the source does.** ADR-0003 stays in force: the image
is not published to any public registry. Anyone outside builds it from source.

**Inbound contributions are under the Developer Certificate of Origin 1.1.** Every commit
carries a `Signed-off-by:` trailer from its author. Two gates enforce it:

- a lefthook `commit-msg` hook rejects an unsigned commit locally;
- a CI job checks every non-merge commit in a pull request (`bin/check-dco.sh`), because
  contributors run none of this repository's hooks.

Neither gate signs anything. Only the human contributor adds the trailer; an assistant or
script never does. Commits made before this decision carry no sign-off and are not
rewritten.

**AI-assisted contributions are permitted, with no disclosure rule.** The contributor's
sign-off covers AI-assisted work exactly as it covers anything else they submit.

Both terms are stated in `CONTRIBUTING.md`.

## Alternatives Considered

| Option | Pros | Cons | Decision |
|---|---|---|---|
| DCO 1.1, enforced | One line per commit; checkable in CI; same as `mmd2tex` | Assisted commits must be handed back to a human to sign | **Selected** |
| DCO stated, not enforced | No friction for the maintainer | A term nothing checks is a term nobody meets | Rejected |
| CLA | Can grant patents and allow relicensing | Contributors may need their employer's signature; no stated need for either grant | Rejected |
| No stated terms | Zero friction | Relicensing later needs every contributor's agreement | Rejected |
| Also publish the image | One `pull` for consumers | Insecure constants by design; GPL aggregate needs its own analysis | Rejected (ADR-0003) |

## Consequences

**Positive**: the choice that cannot be made later is made before it matters. Going public
becomes a checklist rather than a decision about terms.

**Negative**: this repository's own commits now need a human sign-off. An assistant stages
its work and hands it back unsigned rather than committing it.

**Still required before the repository is made public** (not decided here):

- `SECURITY.md` with a reporting contact, and `CODE_OF_CONDUCT.md`;
- issue and PR templates;
- README and workflow wording that assumes the internal registry;
- CodeQL, dependency review and OpenSSF Scorecard, gated on the repository being public;
- repository topics, and branch protection on `main`;
- an actual consumer, which the project does not yet have;
- updating the distribution profile in `CLAUDE.md`, when this record is Accepted.
