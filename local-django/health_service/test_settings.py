"""Isolated SQLite settings used only by the repository test runner."""

import os


os.environ.setdefault(
    "DJANGO_SECRET_KEY",
    "drive-aura-django-test-secret-not-for-production",
)

from .settings import *  # noqa: E402,F403


DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }
}
