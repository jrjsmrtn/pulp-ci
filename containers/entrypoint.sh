#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# Brings up a Pulp API suitable for integration tests, in one container, with
# no supervisor. There are three processes and they are managed by the shell:
# `wait -n` returns when the FIRST one exits, and the trap kills the rest.
#
# That matters more than it looks. Under a supervisor, a dead worker leaves the
# API answering 200 while nothing processes tasks, and the test suite hangs
# until its own timeout with no useful error. Here the container exits, and CI
# reports a crash instead of a timeout.

set -euo pipefail

: "${POSTGRES_HOST:=127.0.0.1}"
: "${POSTGRES_PORT:=5432}"
: "${PULP_ADMIN_PASSWORD:=password}"

# Wait for the database service container. CI starts both at once, and
# `migrate` against a PostgreSQL that is still initialising fails outright
# rather than retrying.
for _ in $(seq 1 60); do
	if python -c "
import socket, sys
s = socket.socket()
s.settimeout(1)
try:
    s.connect(('${POSTGRES_HOST}', int('${POSTGRES_PORT}')))
except OSError:
    sys.exit(1)
" 2>/dev/null; then
		break
	fi
	sleep 1
done

pulpcore-manager migrate --noinput

# Idempotent: re-running it on an existing database just resets the password.
pulpcore-manager reset-admin-password --password "${PULP_ADMIN_PASSWORD}"

pids=()
# shellcheck disable=SC2329  # invoked by the trap below, not by name
cleanup() {
	trap - TERM INT
	kill "${pids[@]}" 2>/dev/null || true
	wait "${pids[@]}" 2>/dev/null || true
}
trap cleanup EXIT TERM INT

pulpcore-api --bind "0.0.0.0:24817" &
pids+=("$!")

pulpcore-content --bind "0.0.0.0:24816" &
pids+=("$!")

pulpcore-worker &
pids+=("$!")

# Returns as soon as any one of them dies, which is the point.
wait -n "${pids[@]}"
exit $?
