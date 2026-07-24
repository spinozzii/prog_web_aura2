import os

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "replace-with-a-local-secret")
DEBUG = False
ALLOWED_HOSTS = ["localhost", "127.0.0.1", "testserver"]
ROOT_URLCONF = "health_service.urls"
MIDDLEWARE = []
INSTALLED_APPS = []
DATABASES = {}
USE_TZ = True
DEFAULT_CHARSET = "utf-8"
