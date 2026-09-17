<!--
SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
SPDX-License-Identifier: Apache-2.0
-->

## What and why

<!-- What this changes, and which integration test or problem it serves. -->

## Checklist

- [ ] Every commit is signed off (`git commit -s`); see CONTRIBUTING.md, "Contribution terms"
- [ ] Branched from `develop`
- [ ] `CHANGELOG.md` updated under `[Unreleased]`, if a user of the image would notice
- [ ] Any size or start-up figure quoted here or in docs was printed by `bin/measure.sh`,
      and says whether a size is compressed or on disk
- [ ] If the image changed: `bin/measure.sh` and the grype scan pass locally
