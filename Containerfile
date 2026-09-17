# SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# A Pulp image for CI integration testing. See CLAUDE.md for what is
# deliberately absent (Redis, nginx, an embedded database, a supervisor) and
# why each absence is a design decision rather than an omission.

# Base image: pinned by the digest of its multi-arch OCI index, so a rebuild
# gets exactly the base that was reviewed and scanned, on both amd64 and arm64.
# The tag stays for readability and for Dependabot, which proposes a new digest
# as a pull request that CI then scans. Both FROM lines must carry the same
# reference, because the venv built in the first stage runs in the second.
# The tag is literal rather than an ARG: Dependabot cannot update a FROM that
# is built from an argument, and a pinned digest ignores a tag that disagrees.
#
# To check the pin by hand, the registry must answer with the same digest:
#   curl -sI -H "Authorization: Bearer $TOKEN" \
#     -H 'Accept: application/vnd.oci.image.index.v1+json' \
#     https://registry-1.docker.io/v2/library/python/manifests/3.13-slim

# --- build stage -----------------------------------------------------------
# Compilers live here and nowhere else. Anything without an arm64/amd64 wheel
# is built in this stage; the runtime stage never gains a toolchain.
FROM docker.io/library/python:3.13-slim@sha256:9d2e5553305c7c7b0097999bb17187c69b921ccd6bc9d40e4bb5ebe652c00285 AS build

RUN apt-get update \
	&& apt-get install --no-install-recommends --assume-yes \
		build-essential \
	&& rm -rf /var/lib/apt/lists/*

# A venv rather than --user or --target: it copies as a single self-contained
# directory, and both stages share the same base image, so the interpreter ABI
# it was built against is the one that will run it.
ENV VIRTUAL_ENV=/opt/venv
RUN python -m venv "${VIRTUAL_ENV}"
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# pulpcore pulls psycopg[binary], which vendors its own libpq. That is what
# makes a slim Debian base viable without postgresql-client packages, and is
# the reason this is not built on UBI.
RUN pip install --no-cache-dir --upgrade pip \
	&& pip install --no-cache-dir \
		pulpcore \
		pulp-file

# Record exactly what was resolved. Unpinned installs are fine for a fixture
# that is rebuilt per run, but a build whose contents cannot be enumerated
# afterwards is not measurable.
RUN pip freeze > "${VIRTUAL_ENV}/requirements.lock"

# --- runtime stage ---------------------------------------------------------
FROM docker.io/library/python:3.13-slim@sha256:9d2e5553305c7c7b0097999bb17187c69b921ccd6bc9d40e4bb5ebe652c00285

ENV VIRTUAL_ENV=/opt/venv \
	PATH="/opt/venv/bin:${PATH}" \
	PULP_SETTINGS=/etc/pulp/settings.py \
	PYTHONUNBUFFERED=1 \
	PYTHONDONTWRITEBYTECODE=1

# Debian publishes security fixes faster than python:*-slim is rebuilt: on
# 2026-09-17 a base pulled that morning carried 21 High/Critical findings that
# Debian had already fixed (libc6, perl-base, libpcre2, libsqlite3, gzip), and
# this upgrade cleared all of them. It costs a layer of replaced files, because
# the base layer underneath cannot shrink. The CI scan (.grype.yaml) is what
# notices if it stops being enough.
RUN apt-get update \
	&& apt-get upgrade --assume-yes --no-install-recommends \
	&& rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/venv /opt/venv

# Runs as a normal user: CI runners vary in how they treat root-owned
# bind-mounted volumes, and nothing here needs privilege.
RUN useradd --uid 1000 --create-home --shell /bin/bash pulp \
	&& mkdir -p /etc/pulp/certs /var/lib/pulp/media /var/lib/pulp/tmp \
	&& chown -R pulp:pulp /var/lib/pulp

# pulpcore refuses to start without this file -- it encrypts secret fields in
# the database, and a missing one is an ImproperlyConfigured at import time,
# before migrate. Generated at build time rather than committed: a Fernet key
# in the repository is a secret-shaped string that every scanner will flag, and
# this one protects nothing, since the database it encrypts is destroyed with
# the job.
RUN python -c \
	"from cryptography.fernet import Fernet; import pathlib; \
	pathlib.Path('/etc/pulp/certs/database_fields.symmetric.key').write_bytes(Fernet.generate_key())" \
	&& chown pulp:pulp /etc/pulp/certs/database_fields.symmetric.key \
	&& chmod 0400 /etc/pulp/certs/database_fields.symmetric.key

COPY containers/settings.py /etc/pulp/settings.py
COPY containers/entrypoint.sh /usr/local/bin/pulp-ci-entrypoint

RUN chmod 0755 /usr/local/bin/pulp-ci-entrypoint

# Collect Django's static files at build time. Needs no database, and doing it
# here rather than in the entrypoint keeps it out of the measured start-up.
# Without it every request logs "No directory at: /var/lib/pulp/assets/".
RUN pulpcore-manager collectstatic --noinput --clear \
	&& chown -R pulp:pulp /var/lib/pulp/assets

USER pulp
WORKDIR /var/lib/pulp

# 24817 API, 24816 content. Upstream merges these behind nginx; a test client
# can address two ports, so the proxy is not built in.
EXPOSE 24817 24816

ENTRYPOINT ["/usr/local/bin/pulp-ci-entrypoint"]
