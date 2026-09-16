#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# Builds the image, measures it, and proves it works — in that order, because
# a size measurement of an image that cannot serve the API is worthless.
#
# The readiness signal is deliberately NOT "the port accepts a connection" or
# "HTTP answered". Both are true of a Pulp whose database is unreachable and
# whose worker is dead, which is exactly the state that makes an integration
# suite hang. What is measured here is the condition the suite actually needs:
#
#   /pulp/api/v3/status/ returns 200 AND database_connection.connected is true
#   AND online_workers is non-empty.
#
# Sizes reported are podman's image size (uncompressed, on disk), the same
# figure quoted for the upstream baseline. It is not the registry download size.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

IMAGE="${IMAGE:-localhost/pulp-ci:dev}"
PG_IMAGE="${PG_IMAGE:-docker.io/library/postgres:17-alpine}"
NET="pulp-ci-measure"
PG_NAME="pulp-ci-measure-db"
APP_NAME="pulp-ci-measure-app"
API_PORT="${API_PORT:-24817}"
ADMIN_PASSWORD="measure-only"
TIMEOUT="${TIMEOUT:-300}"

mkdir -p measurements

now() { python3 -c 'import time; print(f"{time.time():.3f}")'; }

cleanup() {
	podman rm --force --ignore "${APP_NAME}" "${PG_NAME}" >/dev/null 2>&1 || true
	podman network rm --force "${NET}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cleanup

echo "==> building ${IMAGE}"
build_start=$(now)
podman build --tag "${IMAGE}" --file Containerfile .
build_end=$(now)

# --format with an explicit field: `podman images` prints a human-rounded
# string ("520 MB"), which cannot be compared across runs.
size_bytes=$(podman image inspect --format '{{.Size}}' "${IMAGE}")
arch=$(podman image inspect --format '{{.Architecture}}' "${IMAGE}")
layers=$(podman image inspect --format '{{len .RootFS.Layers}}' "${IMAGE}")

echo "==> starting postgres and the app"
podman network create "${NET}" >/dev/null

podman run --detach --name "${PG_NAME}" --network "${NET}" \
	--env POSTGRES_DB=pulp \
	--env POSTGRES_USER=pulp \
	--env POSTGRES_PASSWORD=pulp \
	"${PG_IMAGE}" >/dev/null

start_ts=$(now)
podman run --detach --name "${APP_NAME}" --network "${NET}" \
	--publish "${API_PORT}:24817" \
	--env "POSTGRES_HOST=${PG_NAME}" \
	--env POSTGRES_DB=pulp \
	--env POSTGRES_USER=pulp \
	--env POSTGRES_PASSWORD=pulp \
	--env "PULP_ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
	"${IMAGE}" >/dev/null

echo "==> waiting for a usable API on :${API_PORT}"
ready_ts=""
first_failure=""
end_by=$(python3 -c "import time; print(f'{time.time() + ${TIMEOUT}:.3f}')")

while :; do
	body=$(curl --silent --show-error --max-time 5 \
		--user "admin:${ADMIN_PASSWORD}" \
		"http://127.0.0.1:${API_PORT}/pulp/api/v3/status/" 2>&1 || true)

	# Gate on the contents, not on curl's exit status: a 500 page and an
	# unreachable database both produce a non-empty body.
	verdict=$(printf '%s' "${body}" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    print("not-json")
    sys.exit()
db = d.get("database_connection", {}).get("connected")
workers = d.get("online_workers") or []
if db and workers:
    print("ready")
else:
    print(f"unready db={db} workers={len(workers)}")
' 2>/dev/null || echo "not-json")

	if [ "${verdict}" = "ready" ]; then
		ready_ts=$(now)
		break
	fi

	[ -n "${first_failure}" ] || first_failure="${verdict}"

	if [ "$(python3 -c "import time; print(1 if time.time() > ${end_by} else 0)")" = "1" ]; then
		echo "TIMED OUT after ${TIMEOUT}s; last verdict: ${verdict}" >&2
		podman logs --tail 40 "${APP_NAME}" >&2 || true
		exit 1
	fi
	sleep 1
done

elapsed=$(python3 -c "print(f'{${ready_ts} - ${start_ts}:.1f}')")
build_secs=$(python3 -c "print(f'{${build_end} - ${build_start}:.1f}')")
size_mb=$(python3 -c "print(f'{${size_bytes} / 1000 / 1000:.0f}')")

# Pull the resolved dependency set out of the image while it is still running.
podman exec "${APP_NAME}" cat /opt/venv/requirements.lock >measurements/requirements.lock
pulpcore_version=$(grep -i '^pulpcore==' measurements/requirements.lock | head -1)

stamp=$(date +%Y-%m-%dT%H:%M:%S%z)
out="measurements/$(date +%Y%m%d-%H%M%S)-${arch}.json"
cat >"${out}" <<EOF
{
  "measured_at": "${stamp}",
  "image": "${IMAGE}",
  "architecture": "${arch}",
  "size_bytes": ${size_bytes},
  "size_mb": ${size_mb},
  "layers": ${layers},
  "build_seconds_with_existing_cache": ${build_secs},
  "seconds_to_usable_api": ${elapsed},
  "readiness_criterion": "status 200 with database_connection.connected true and online_workers non-empty",
  "first_poll_verdict": "${first_failure}",
  "pulpcore": "${pulpcore_version}",
  "postgres_image": "${PG_IMAGE}"
}
EOF

echo
echo "  size:              ${size_mb} MB (${size_bytes} bytes, ${layers} layers, ${arch})"
echo "  build:             ${build_secs}s"
echo "  usable API after:  ${elapsed}s"
echo "  first poll said:   ${first_failure}"
echo "  ${pulpcore_version}"
echo "  written to ${out}"
