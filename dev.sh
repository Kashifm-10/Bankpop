#!/usr/bin/env bash
# Both halves of Bankpop on this machine: the mail service and the app.
#
#   ./dev.sh              start the mail service, then the app (Ctrl-C stops both)
#   ./dev.sh app          the app alone, against a mail service you started yourself
#   ./dev.sh mail         the mail service in this terminal, for its logs
#   ./dev.sh stop         stop a mail service left running in the background
#   ./dev.sh status       ask the running mail service whether it can send
#
# Where the app finds the service: it posts to http://127.0.0.1:8000 whenever
# the page it is served from is localhost (see MailApi.resolveBaseUrl), so this
# script passes no URL for a browser build - only the token, which the service
# refuses a message without. The token is read from django-mail-api/.env, so
# there is one place to change it.
#
# MAIL_PORT=8001 ./dev.sh   moves the service, and the app follows
# DEVICE=web-server ./dev.sh  serves the app on a port instead of opening Chrome
set -euo pipefail

cd "$(dirname "$0")"
ROOT=$(pwd)
APP_DIR="$ROOT/app"
MAIL_DIR="$ROOT/django-mail-api"
STATE_DIR="$ROOT/.dev"
MAIL_LOG="$STATE_DIR/mail.log"
MAIL_PID_FILE="$STATE_DIR/mail.pid"
MAIL_PORT="${MAIL_PORT:-8000}"
DEVICE="${DEVICE:-chrome}"

say() { printf '%s\n' "$*"; }

die() {
  printf 'dev.sh: %s\n' "$*" >&2
  exit 1
}

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
}

# The service's own interpreter: the project's virtualenv, which `uv sync`
# creates in django-mail-api/.venv.
python_bin() {
  if [ -x "$MAIL_DIR/.venv/Scripts/python.exe" ]; then
    printf '%s' "$MAIL_DIR/.venv/Scripts/python.exe"
  elif [ -x "$MAIL_DIR/.venv/bin/python" ]; then
    printf '%s' "$MAIL_DIR/.venv/bin/python"
  else
    return 1
  fi
}

# MAIL_API_TOKEN out of django-mail-api/.env, without printing it.
mail_token() {
  [ -f "$MAIL_DIR/.env" ] ||
    die "django-mail-api/.env is missing: copy .env.example to .env and fill it in."

  local token
  token=$(sed -n 's/^[[:space:]]*MAIL_API_TOKEN=//p' "$MAIL_DIR/.env" |
    tail -1 | tr -d '\r' | sed 's/[[:space:]]*$//')
  token=${token%\"}; token=${token#\"}
  token=${token%\'}; token=${token#\'}

  [ -n "$token" ] || die "MAIL_API_TOKEN is empty in django-mail-api/.env."
  printf '%s' "$token"
}

healthy() {
  curl -fsS -m 2 "http://127.0.0.1:$MAIL_PORT/api/health/" >/dev/null 2>&1
}

stop_pid() {
  kill "$1" 2>/dev/null || true
  sleep 1
  if kill -0 "$1" 2>/dev/null; then
    # Git Bash can start a native Windows process it cannot signal.
    command -v taskkill >/dev/null 2>&1 &&
      taskkill //PID "$1" //F >/dev/null 2>&1 || true
  fi
}

start_mail() {
  mkdir -p "$STATE_DIR"

  if healthy; then
    say "A mail service is already answering on :$MAIL_PORT; using it."
    return 0
  fi

  local python
  python=$(python_bin) ||
    die "django-mail-api/.venv is missing. Run: cd django-mail-api && uv sync"

  say "Starting the mail service on http://127.0.0.1:$MAIL_PORT ..."
  (
    cd "$MAIL_DIR"
    nohup "$python" manage.py runserver "127.0.0.1:$MAIL_PORT" --noreload \
      >"$MAIL_LOG" 2>&1 &
    echo $! >"$MAIL_PID_FILE"
  )

  local waited=0
  while [ "$waited" -lt 40 ]; do
    if healthy; then
      say "Mail service ready: $(curl -fsS "http://127.0.0.1:$MAIL_PORT/api/health/")"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  say "The mail service did not start. Its log:"
  tail -20 "$MAIL_LOG" >&2 || true
  return 1
}

stop_mail() {
  [ -f "$MAIL_PID_FILE" ] || {
    say "No mail service was started by dev.sh."
    return 0
  }

  local pid
  pid=$(cat "$MAIL_PID_FILE")
  if kill -0 "$pid" 2>/dev/null; then
    stop_pid "$pid"
    say "Stopped the mail service (pid $pid)."
  else
    say "The mail service had already stopped."
  fi
  rm -f "$MAIL_PID_FILE"
}

run_app() {
  command -v flutter >/dev/null 2>&1 ||
    die "Flutter is not on PATH. Install it, or use: docker compose up"

  local token
  token=$(mail_token)

  local defines=("--dart-define=MAIL_API_TOKEN=$token")
  case "$DEVICE" in
    chrome | edge | web-server)
      # A browser on this machine reaches the service on loopback. A phone
      # would need the hosted address instead, which the app picks up by
      # itself, so this define is only added for a local browser.
      defines+=("--dart-define=MAIL_API_URL=http://127.0.0.1:$MAIL_PORT")
      ;;
  esac

  say "Starting the app (device: $DEVICE, mail: http://127.0.0.1:$MAIL_PORT)"
  cd "$APP_DIR"
  flutter pub get
  # Not exec: quitting the app has to run the EXIT trap, which stops the mail
  # service that `./dev.sh` started.
  flutter run -d "$DEVICE" "${defines[@]}"
}

case "${1:-all}" in
all)
  start_mail || exit 1
  trap 'stop_mail' EXIT INT TERM
  run_app
  ;;
app)
  run_app
  ;;
mail)
  python=$(python_bin) ||
    die "django-mail-api/.venv is missing. Run: cd django-mail-api && uv sync"
  say "Mail service on http://127.0.0.1:$MAIL_PORT (Ctrl-C stops it)"
  cd "$MAIL_DIR"
  exec "$python" manage.py runserver "127.0.0.1:$MAIL_PORT"
  ;;
stop)
  stop_mail
  ;;
status)
  healthy || die "Nothing is answering on http://127.0.0.1:$MAIL_PORT."
  curl -fsS "http://127.0.0.1:$MAIL_PORT/api/health/"
  printf '\n'
  ;;
help | --help | -h)
  usage
  ;;
*)
  usage >&2
  exit 1
  ;;
esac
