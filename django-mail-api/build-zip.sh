#!/bin/sh
# Builds dist/django-mail-api.zip for drag-and-drop deploys (e.g. Wasmer Edge).
#
# Needs `uv` (it exports the pinned requirements) and either `zip` or Python.
# Git Bash on Windows usually has Python but not `zip`, so the archive is built
# with Python when `zip` is missing - same contents either way.
set -eu
cd "$(dirname "$0")"

uv export --no-hashes --no-dev --format requirements-txt -o requirements.txt -q
mkdir -p dist
rm -f dist/django-mail-api.zip
find . -name __pycache__ -not -path './.venv/*' -exec rm -rf {} + 2>/dev/null || true

if command -v zip >/dev/null 2>&1; then
  zip -qr dist/django-mail-api.zip . -x '.venv/*' '.git/*' 'dist/*' '.env' \
    'flutter_client/*' 'postman/*' 'staticfiles/*'
else
  # The interpreter that runs manage.py, so no extra dependency is needed.
  PYTHON=python
  [ -x .venv/Scripts/python.exe ] && PYTHON=.venv/Scripts/python.exe
  [ -x .venv/bin/python ] && PYTHON=.venv/bin/python
  "$PYTHON" - <<'PY'
import os
import zipfile

SKIP_DIRS = {'.venv', '.git', 'dist', 'flutter_client', 'postman', 'staticfiles', '__pycache__'}
SKIP_FILES = {'.env'}

with zipfile.ZipFile('dist/django-mail-api.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for name in files:
            if name in SKIP_FILES or name.endswith('.pyc'):
                continue
            path = os.path.join(root, name)
            # Forward slashes: the host unpacks this on Linux.
            archive.write(path, os.path.relpath(path, '.').replace(os.sep, '/'))
print('wrote dist/django-mail-api.zip')
PY
fi

echo "built dist/django-mail-api.zip"
