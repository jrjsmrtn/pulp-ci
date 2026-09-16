#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# Exercises the API the way an integration suite would, and fails loudly if it
# cannot. This is what CI runs after bringing the stack up, and what you run
# locally against a container you started by hand:
#
#   bin/smoke-test.sh [base-url] [admin-password]
#
# It lives here rather than inside the workflow YAML for two reasons: it is
# runnable locally, and shellcheck/shfmt already gate it. Assertions embedded in
# a `run:` block are neither.
#
# The checks deliberately go past "the API answered". A Pulp with an unreachable
# database or a dead worker still answers, and still returns 200 on some
# endpoints -- so this asserts the status contract *and* performs a real write,
# reads it back, and cleans up.

set -euo pipefail

BASE="${1:-http://localhost:24817}"
PASSWORD="${2:-${PULP_ADMIN_PASSWORD:-password}}"
AUTH="admin:${PASSWORD}"
REPO_NAME="ci-smoke-test-$$"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/check_status.py" <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))

if not d.get("database_connection", {}).get("connected"):
    sys.exit("FAIL: database_connection.connected is false")

workers = d.get("online_workers") or []
if not workers:
    sys.exit("FAIL: no online workers -- tasks would queue forever")

print("  workers:    " + ", ".join(w["name"] for w in workers))
print("  components: " + ", ".join(
    "{} {}".format(c["component"], c["version"]) for c in d["versions"]
))
PY

cat >"$tmp/read_href.py" <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))
href = d.get("pulp_href")
if not href:
    sys.exit("FAIL: create returned no pulp_href: {}".format(d))
print(href)
PY

cat >"$tmp/check_repo.py" <<'PY'
import json
import sys

path, expected = sys.argv[1], sys.argv[2]
d = json.load(open(path))
if d.get("name") != expected:
    sys.exit("FAIL: read back {!r}, expected {!r}".format(d.get("name"), expected))
print("  read back:  " + d["name"])
PY

echo "==> status endpoint reports a usable API"
curl -sf --max-time 15 -u "$AUTH" "${BASE}/pulp/api/v3/status/" -o "$tmp/status.json"
python3 "$tmp/check_status.py" "$tmp/status.json"

echo "==> create a file repository"
curl -sf --max-time 30 -u "$AUTH" -X POST \
	-H 'Content-Type: application/json' \
	-d "{\"name\":\"${REPO_NAME}\"}" \
	"${BASE}/pulp/api/v3/repositories/file/file/" -o "$tmp/created.json"
href=$(python3 "$tmp/read_href.py" "$tmp/created.json")
echo "  created:    ${href}"

echo "==> read it back"
curl -sf --max-time 15 -u "$AUTH" "${BASE}${href}" -o "$tmp/fetched.json"
python3 "$tmp/check_repo.py" "$tmp/fetched.json" "$REPO_NAME"

# Deletion is asynchronous -- Pulp answers 202 with a task href. Not waiting for
# it: the point of this step is to leave nothing behind, not to test tasking.
echo "==> delete it"
code=$(curl -s --max-time 30 -u "$AUTH" -X DELETE -o /dev/null -w '%{http_code}' "${BASE}${href}")
case "$code" in
	2*) echo "  delete accepted (HTTP ${code})" ;;
	*) echo "FAIL: delete returned HTTP ${code}" >&2 && exit 1 ;;
esac

echo "==> smoke test passed"
