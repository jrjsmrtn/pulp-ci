# SPDX-FileCopyrightText: 2026 Georges Martin <jrjsmrtn@gmail.com>
# SPDX-License-Identifier: Apache-2.0
#
# pulpcore settings for CI integration testing. Loaded by dynaconf from
# /etc/pulp/settings.py; every value here can still be overridden by a PULP_*
# environment variable, which is how the harness points the image at its
# database.
#
# This file assumes it is running in a disposable container on a CI network.
# Several settings below would be indefensible anywhere else, and are marked.

import os

# --- Database --------------------------------------------------------------
# A CI service container, not part of this image. pulpcore needs PostgreSQL;
# it is the only external service it needs, because of WORKER_TYPE below.
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": os.environ.get("POSTGRES_DB", "pulp"),
        "USER": os.environ.get("POSTGRES_USER", "pulp"),
        "PASSWORD": os.environ.get("POSTGRES_PASSWORD", "pulp"),
        "HOST": os.environ.get("POSTGRES_HOST", "127.0.0.1"),
        "PORT": os.environ.get("POSTGRES_PORT", "5432"),
    }
}

# --- Why there is no Redis -------------------------------------------------
# These two settings are the whole reason. "pulpcore" workers coordinate
# through PostgreSQL advisory locks instead of Redis, and the content-app
# cache is the only other consumer. Turn either back on and Redis becomes a
# required service again, which doubles the CI compose file.
WORKER_TYPE = "pulpcore"
CACHE_ENABLED = False

# --- Content ---------------------------------------------------------------
# The content app serves published artifacts on its own port. Upstream merges
# it with the API behind nginx; here the test client addresses both directly,
# so CONTENT_ORIGIN must name the content app's own address.
CONTENT_ORIGIN = os.environ.get("PULP_CONTENT_ORIGIN", "http://localhost:24816")
MEDIA_ROOT = os.environ.get("PULP_MEDIA_ROOT", "/var/lib/pulp/media")

# --- Deliberately insecure, CI only ----------------------------------------
# A fixed key in a public file. This is safe only because the image is
# disposable and must never run outside CI; it is written down rather than
# generated so that a restarted container can still read sessions it signed.
SECRET_KEY = os.environ.get("PULP_SECRET_KEY", "pulp-ci-insecure-fixed-key")

# The container is addressed by whatever name the CI runner gives it.
ALLOWED_HOSTS = ["*"]

# --- Off in CI -------------------------------------------------------------
# pulpcore posts anonymous analytics on a schedule by default. A test fixture
# that phones out on every run is both noise and a network dependency.
#
# ANALYTICS only: the older TELEMETRY name still works but logs a deprecation
# warning on every start (observed with pulpcore 3.118.0, 2026-09-16), and a
# fixture whose log opens with a warning trains people to ignore its log.
ANALYTICS = False
