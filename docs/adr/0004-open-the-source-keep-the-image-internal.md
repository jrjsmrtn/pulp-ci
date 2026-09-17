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

**Consumers build the image from source into a registry they control** (decided
2026-09-17). A consumer's CI builds from a release tag of this repository and pushes the
result to its own registry. This project publishes **no image to GHCR**, public or
private:

- a **public** package would redistribute the insecure-by-design, GPL-bundling image that
  ADR-0003 keeps internal;
- a **private** package under the maintainer's personal account cannot be pulled by
  another organisation's CI token. Pulling it would mean storing the maintainer's personal
  access token in that organisation's CI secrets, tying a personal account to someone
  else's infrastructure.

Building from source leaves each consumer holding its own copy of the image, under its own
registry's access controls, and responsible for its own internal redistribution of it.

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
| Consumers build from source into their own registry | No personal credentials in a consumer's CI; each consumer controls its copy | Each consumer runs its own build, and multi-arch builds if needed | **Selected** |
| Public GHCR image | Pull-and-go for everyone | Same objections as publishing the image anywhere public | Rejected |
| Private GHCR image under the personal account | Hosted runners can pull without rebuilding | Another organisation's CI token cannot read it; would need a personal token in that organisation's secrets; package visibility can be flipped to public irreversibly | Rejected |

## Consequences

**Positive**: the choice that cannot be made later is made before it matters. Going public
becomes a checklist rather than a decision about terms.

**Negative**: this repository's own commits now need a human sign-off. An assistant stages
its work and hands it back unsigned rather than committing it.

**Prepared for going public** (2026-09-17): `SECURITY.md` and `CODE_OF_CONDUCT.md`, both
written for a single maintainer; issue forms and a PR template; README wording that no
longer assumes the private registry; and CodeQL, dependency review and OpenSSF Scorecard
workflows that run only once the repository is public.

**Still required before the repository is made public** (not decided here):

- repository topics, and disabling the unused wiki and projects;
- branch protection on `main`.

**At the moment it is made public:**

- register the repository at <https://api.reuse.software/register>, so the README's REUSE
  badge stops reading "unregistered" (the CI badge starts working on its own);
- add the OpenSSF Scorecard badge once the first Scorecard run has published a score;
- enable private vulnerability reporting, which `SECURITY.md` names as the preferred
  channel;
- update the distribution profile in `CLAUDE.md`, and mark this record Accepted.
