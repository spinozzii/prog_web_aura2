import os

from django.core.exceptions import ImproperlyConfigured


SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")
if not SECRET_KEY:
    raise ImproperlyConfigured("DJANGO_SECRET_KEY non configurata.")
DEBUG = False
ALLOWED_HOSTS = ["localhost", "127.0.0.1", "testserver"]
ROOT_URLCONF = "health_service.urls"
MIDDLEWARE = []
INSTALLED_APPS = ["health_service.apps.HealthServiceConfig"]
if os.environ.get("POSTGRES_DB"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": os.environ["POSTGRES_DB"],
            "USER": os.environ.get("POSTGRES_USER", ""),
            "PASSWORD": os.environ.get("POSTGRES_PASSWORD", ""),
            "HOST": os.environ.get("POSTGRES_HOST", "127.0.0.1"),
            "PORT": os.environ.get("POSTGRES_PORT", "5432"),
            "CONN_MAX_AGE": 0,
        }
    }
else:
    DATABASES = {}
LOCAL_API_SECRET = os.environ.get("LOCAL_API_SECRET", "")
MAX_MIGRATION_REQUEST_BYTES = 1024 * 1024
USE_TZ = True
DEFAULT_CHARSET = "utf-8"
