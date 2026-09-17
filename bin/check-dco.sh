#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# DCO gate for incoming changes: every non-merge commit in a range must carry a
# `Signed-off-by:` trailer whose email matches the commit author's.
#
# Contributors' machines run none of our hooks, so the local commit-msg gate covers
# maintainer commits only; this is the enforcement point for pull requests.
#
#   bin/check-dco.sh <base> <head>     # e.g. origin/develop HEAD
#
# Merge commits are exempt: a merge asserts nothing about authorship of the merged
# work, and its sign-off would be meaningless.
set -euo pipefail

BASE="${1:-}"
HEAD_REF="${2:-HEAD}"

if [ -z "$BASE" ]; then
	echo "usage: $0 <base-ref> [head-ref]" >&2
	exit 2
fi

# Fail loudly rather than silently passing on a range git cannot resolve — an
# unresolvable base would otherwise yield zero commits and look like success.
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null || {
	echo "FAIL: cannot resolve base ref '$BASE' (shallow clone? need fetch-depth: 0)" >&2
	exit 2
}

commits="$(git rev-list --no-merges "$BASE..$HEAD_REF")"

if [ -z "$commits" ]; then
	echo "DCO: no non-merge commits in $BASE..$HEAD_REF — nothing to check"
	exit 0
fi

n=0
bad=0
while read -r sha; do
	[ -n "$sha" ] || continue
	n=$((n + 1))
	author_email="$(git log -1 --format='%ae' "$sha")"
	subject="$(git log -1 --format='%s' "$sha")"
	# Trailer values, one per line (a commit may carry several sign-offs).
	signers="$(git log -1 --format='%(trailers:key=Signed-off-by,valueonly)' "$sha")"

	if [ -z "$signers" ]; then
		echo "FAIL $(git rev-parse --short "$sha")  no Signed-off-by  — $subject"
		bad=$((bad + 1))
		continue
	fi

	# Bots must still sign off, but are exempt from the author-match rule: Dependabot
	# signs as `dependabot[bot] <support@github.com>` while authoring as
	# `…+dependabot[bot]@users.noreply.github.com`, so a strict match would block every
	# dependency-bump PR. A bot has no DCO to certify in the first place; the trailer is
	# a formality, and the identity behind it is GitHub's, not a contributor's.
	case "$author_email" in
		*"[bot]@"* | *"[bot]"*)
			continue
			;;
	esac

	# Case-insensitive match of the author's email against any sign-off.
	if ! printf '%s\n' "$signers" | grep -qiF "<$author_email>"; then
		echo "FAIL $(git rev-parse --short "$sha")  sign-off does not match author <$author_email>  — $subject"
		printf '       found: %s\n' "$signers"
		bad=$((bad + 1))
	fi
done <<<"$commits"

if [ "$bad" -gt 0 ]; then
	cat >&2 <<'MSG'

This project uses the Developer Certificate of Origin (DCO). Every commit needs a
sign-off from its author:

  git commit -s                       # for new commits
  git commit -s --amend --no-edit     # fix the last one
  git rebase --signoff <base>         # fix a whole branch, then force-push

Full terms: CONTRIBUTING.md -> Contribution terms
MSG
	echo "DCO: $bad of $n commit(s) not signed off" >&2
	exit 1
fi

echo "DCO: all $n commit(s) signed off"
