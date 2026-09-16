<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

# 1. Record Architecture Decisions

Date: 2026-09-16

## Status

Accepted

## Context

pulp-ci is small — one Containerfile, one entrypoint, one measurement script — and most of
its content is the result of deciding what to leave out. Those omissions are the entire
value of the project, and they are invisible in the tree: nothing in a Containerfile
records that Redis was considered and found unnecessary, or that nginx was dropped
deliberately rather than forgotten.

That is the failure mode this record guards against. A future reader (or a future AI
session) looking at an image with no reverse proxy will reasonably assume it is incomplete
and add one back.

## Decision

Significant decisions are recorded as ADRs in `docs/adr/`, in Michael Nygard's format,
numbered sequentially with four digits and no gaps. Titles use the adr-tools form
`# N. Title`, which is what Structurizr's `!adrs` importer parses — adopted here for
consistency with sibling projects even though this one has no C4 model.

What warrants an ADR in a project this size:

- **Anything deliberately absent.** A dependency not taken, a service not run, a layer not
  added. These are the decisions that get silently reverted.
- Base image and dependency-management choices.
- Where built artifacts are published.

What does not: file layout, naming, formatting. The tree shows those.

## Consequences

**Positive**: the reasoning behind each absence survives, so the image does not slowly
re-acquire the weight it was built to shed.

**Negative**: three ADRs is a lot of prose for a repository of roughly 400 lines. The bet
is that the ratio inverts the first time someone asks why there is no Redis.

## References

- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) — Michael Nygard
- [adr.github.io](https://adr.github.io/)
