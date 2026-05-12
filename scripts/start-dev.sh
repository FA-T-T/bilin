#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="${ROOT_DIR}/apps/api"
WEB_DIR="${ROOT_DIR}/apps/web"
HOST="${BILIN_DEV_HOST:-127.0.0.1}"
API_PORT="${BILIN_API_PORT:-8000}"
WEB_PORT="${BILIN_WEB_PORT:-5173}"
LOG_DIR="${BILIN_DEV_LOG_DIR:-${ROOT_DIR}/.logs/dev}"
PID_DIR="${LOG_DIR}/pids"
UVICORN_BIN="${API_DIR}/.venv/bin/uvicorn"
BILIN_BIN="${API_DIR}/.venv/bin/bilin"
PYTHON_BIN="${API_DIR}/.venv/bin/python"
PNPM_BIN="${PNPM_BIN:-pnpm}"
CURL_BIN="${CURL_BIN:-curl}"

usage() {
  cat <<EOF
Usage: ./scripts/start-dev.sh [start|status|stop|restart]

Starts the fixed local Ilios development stack:
  API:    http://${HOST}:${API_PORT}
  Web:    http://${HOST}:${WEB_PORT}
  Worker: local job runner

Environment overrides:
  BILIN_DEV_HOST, BILIN_API_PORT, BILIN_WEB_PORT, BILIN_DEV_LOG_DIR, PNPM_BIN
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

ensure_runtime() {
  [ -x "${UVICORN_BIN}" ] || fail "missing ${UVICORN_BIN}; run backend setup once before using this fixed starter"
  [ -x "${BILIN_BIN}" ] || fail "missing ${BILIN_BIN}; run backend setup once before using this fixed starter"
  [ -x "${PYTHON_BIN}" ] || fail "missing ${PYTHON_BIN}; run backend setup once before using this fixed starter"
  command -v "${PNPM_BIN}" >/dev/null 2>&1 || fail "missing pnpm command: ${PNPM_BIN}"
  command -v "${CURL_BIN}" >/dev/null 2>&1 || fail "missing curl command: ${CURL_BIN}"
  [ -d "${ROOT_DIR}/node_modules" ] || fail "missing node_modules; run pnpm install once before using this fixed starter"
  mkdir -p "${LOG_DIR}" "${PID_DIR}"
}

spawn_detached() {
  local cwd="$1"
  local logfile="$2"
  local pidfile="$3"
  shift 3
  "${PYTHON_BIN}" - "${cwd}" "${logfile}" "${pidfile}" "$@" <<'PY'
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

cwd, logfile, pidfile, *command = sys.argv[1:]
Path(logfile).parent.mkdir(parents=True, exist_ok=True)
Path(pidfile).parent.mkdir(parents=True, exist_ok=True)
stream = open(logfile, "ab", buffering=0)
process = subprocess.Popen(
    command,
    cwd=cwd,
    stdin=subprocess.DEVNULL,
    stdout=stream,
    stderr=subprocess.STDOUT,
    start_new_session=True,
    close_fds=True,
)
Path(pidfile).write_text(f"{process.pid}\n", encoding="utf-8")
PY
}

pid_alive() {
  local pid="${1:-}"
  [ -n "${pid}" ] && kill -0 "${pid}" >/dev/null 2>&1
}

read_pidfile() {
  local file="$1"
  [ -f "${file}" ] && sed -n '1p' "${file}" || true
}

api_ok() {
  "${CURL_BIN}" -fsS "http://${HOST}:${API_PORT}/health" >/dev/null 2>&1
}

web_ok() {
  "${CURL_BIN}" -fsSI "http://${HOST}:${WEB_PORT}" >/dev/null 2>&1
}

port_busy() {
  local port="$1"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
}

write_port_pid() {
  local port="$1"
  local pidfile="$2"
  local pid
  pid="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
  [ -n "${pid}" ] && echo "${pid}" > "${pidfile}"
}

adopt_port_pid_if_needed() {
  local port="$1"
  local pidfile="$2"
  local existing
  existing="$(read_pidfile "${pidfile}")"
  if pid_alive "${existing}"; then
    return 0
  fi
  write_port_pid "${port}" "${pidfile}"
}

worker_pid() {
  ps -axo pid=,command= | awk -v needle="${BILIN_BIN} jobs run-worker" '
    index($0, needle) && $0 !~ /rtk / && $0 !~ /awk / { print $1; exit }
  '
}

wait_until() {
  local check_fn="$1"
  local name="$2"
  local log_file="$3"
  local attempts="${4:-75}"
  local index=0
  while [ "${index}" -lt "${attempts}" ]; do
    if "${check_fn}"; then
      echo "${name} ready"
      return 0
    fi
    index=$((index + 1))
    sleep 0.2
  done
  echo "${name} did not become ready; last log lines:" >&2
  tail -n 80 "${log_file}" >&2 || true
  return 1
}

start_api() {
  local pidfile="${PID_DIR}/api.pid"
  local logfile="${LOG_DIR}/api.log"
  if api_ok; then
    adopt_port_pid_if_needed "${API_PORT}" "${pidfile}"
    echo "api already running: http://${HOST}:${API_PORT}"
    return 0
  fi
  port_busy "${API_PORT}" && fail "port ${API_PORT} is occupied, but API health is not OK"
  spawn_detached "${API_DIR}" "${logfile}" "${pidfile}" \
    "${UVICORN_BIN}" bilin_api.main:app --reload --host "${HOST}" --port "${API_PORT}"
  wait_until api_ok "api" "${logfile}"
}

start_worker() {
  local pidfile="${PID_DIR}/worker.pid"
  local logfile="${LOG_DIR}/worker.log"
  local existing
  existing="$(worker_pid || true)"
  if pid_alive "${existing}"; then
    echo "${existing}" > "${pidfile}"
    echo "worker already running: pid ${existing}"
    return 0
  fi
  spawn_detached "${API_DIR}" "${logfile}" "${pidfile}" "${BILIN_BIN}" jobs run-worker
  sleep 0.4
  if pid_alive "$(read_pidfile "${pidfile}")"; then
    echo "worker ready"
    return 0
  fi
  echo "worker failed to stay running; last log lines:" >&2
  tail -n 80 "${logfile}" >&2 || true
  return 1
}

start_web() {
  local pidfile="${PID_DIR}/web.pid"
  local logfile="${LOG_DIR}/web.log"
  if web_ok; then
    adopt_port_pid_if_needed "${WEB_PORT}" "${pidfile}"
    echo "web already running: http://${HOST}:${WEB_PORT}"
    return 0
  fi
  port_busy "${WEB_PORT}" && fail "port ${WEB_PORT} is occupied, but web is not responding"
  spawn_detached "${ROOT_DIR}" "${logfile}" "${pidfile}" \
    "${PNPM_BIN}" --dir "${WEB_DIR}" dev --host "${HOST}" --port "${WEB_PORT}"
  wait_until web_ok "web" "${logfile}"
}

start_all() {
  ensure_runtime
  start_api
  start_worker
  start_web
  echo "ready: api http://${HOST}:${API_PORT}/health"
  echo "ready: web http://${HOST}:${WEB_PORT}"
  echo "logs: ${LOG_DIR}"
}

status_one() {
  local name="$1"
  local pidfile="$2"
  local pid
  pid="$(read_pidfile "${pidfile}")"
  if pid_alive "${pid}"; then
    echo "${name}: pid ${pid}"
  else
    echo "${name}: no pidfile process"
  fi
}

status_all() {
  mkdir -p "${LOG_DIR}" "${PID_DIR}"
  if api_ok; then
    adopt_port_pid_if_needed "${API_PORT}" "${PID_DIR}/api.pid"
    echo "api: healthy http://${HOST}:${API_PORT}/health"
  else
    status_one "api" "${PID_DIR}/api.pid"
  fi
  local existing_worker
  existing_worker="$(worker_pid || true)"
  if pid_alive "${existing_worker}"; then
    echo "${existing_worker}" > "${PID_DIR}/worker.pid"
    echo "worker: pid ${existing_worker}"
  else
    status_one "worker" "${PID_DIR}/worker.pid"
  fi
  if web_ok; then
    adopt_port_pid_if_needed "${WEB_PORT}" "${PID_DIR}/web.pid"
    echo "web: healthy http://${HOST}:${WEB_PORT}"
  else
    status_one "web" "${PID_DIR}/web.pid"
  fi
  echo "logs: ${LOG_DIR}"
}

stop_pidfile() {
  local name="$1"
  local pidfile="$2"
  local pid
  pid="$(read_pidfile "${pidfile}")"
  if ! pid_alive "${pid}"; then
    rm -f "${pidfile}"
    echo "${name}: not running"
    return 0
  fi
  kill "${pid}" >/dev/null 2>&1 || true
  local index=0
  while [ "${index}" -lt 25 ]; do
    if ! pid_alive "${pid}"; then
      rm -f "${pidfile}"
      echo "${name}: stopped"
      return 0
    fi
    index=$((index + 1))
    sleep 0.2
  done
  kill -9 "${pid}" >/dev/null 2>&1 || true
  rm -f "${pidfile}"
  echo "${name}: killed"
}

stop_all() {
  mkdir -p "${PID_DIR}"
  stop_pidfile "web" "${PID_DIR}/web.pid"
  stop_pidfile "worker" "${PID_DIR}/worker.pid"
  stop_pidfile "api" "${PID_DIR}/api.pid"
}

action="${1:-start}"
case "${action}" in
  start)
    start_all
    ;;
  status)
    status_all
    ;;
  stop)
    stop_all
    ;;
  restart)
    stop_all
    start_all
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
