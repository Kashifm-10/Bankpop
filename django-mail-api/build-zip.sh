#!/bin/sh
# Builds dist/django-mail-api.zip for drag-and-drop deploys (e.g. Wasmer Edge).
set -eu
cd "$(dirname "$0")"
uv export --no-hashes --no-dev --format requirements-txt -o requirements.txt -q
mkdir -p dist
rm -f dist/django-mail-api.zip
find . -name __pycache__ -not -path './.venv/*' -exec rm -rf {} +
zip -qr dist/django-mail-api.zip . -x '.venv/*' '.git/*' 'dist/*' '.env' 'flutter_client/*' 'postman/*'
echo "built dist/django-mail-api.zip"
