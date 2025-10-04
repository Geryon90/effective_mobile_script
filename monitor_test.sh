#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

LOCK="/var/lock/monitor_test.lock"
NAME="test"
MONITOR_URL="${MONITOR_URL:-https://test.com/monitoring/test/api}"
PID_DIR="/var/lib/monitor_test"
LAST_PID_FILE="$PID_DIR/last_pid"
LOG_FILE="/var/log/monitoring.log"
CURL_TIMEOUT=10
CURL_RETRIES=2

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# --- Блокировка: если не удалось открыть LOCK -> логируем и выходим.
exec 9>"$LOCK" 2>/dev/null || {
  echo "$(timestamp) ERROR: cannot open lock file $LOCK" >> "$LOG_FILE" || true
  exit 0
}
# Неблокирующая попытка взять lock — если занято, тихо выходим.
if ! flock -n 9; then
  exit 0
fi

# Гарантируем наличие каталога состояния
mkdir -p "$PID_DIR"

# --- Получаем текущий список PID (одна строка, разделённая пробелами)
current_list="$(pgrep -x "$NAME" | sort -n | tr '\n' ' ' | sed -E 's/ +$//')"

# Если процесса нет — ничего не делаем (по условию)
if [ -z "$current_list" ]; then
  exit 0
fi

# --- Читаем предыдущий список PID, если есть
prev_list=""
if [ -f "$LAST_PID_FILE" ]; then
  prev_list="$(cat "$LAST_PID_FILE" || true)"
fi

# --- Если списки отличаются — логируем рестарт
if [ -n "$prev_list" ] && [ "$prev_list" != "$current_list" ]; then
  echo "$(timestamp) INFO: process '$NAME' restarted: old_pids=$prev_list new_pids=$current_list" >> "$LOG_FILE"
fi

# --- Атомарная запись текущего списка PID
tmpfile="$(mktemp "$PID_DIR/last_pid.XXXXXX")"
printf '%s' "$current_list" > "$tmpfile"
mv "$tmpfile" "$LAST_PID_FILE"

# --- Запрос к мониторинговому серверу (curl). Отключаем errexit, чтобы корректно обработать ошибки.
set +e
curl_args=( --silent --show-error --fail --max-time "$CURL_TIMEOUT" --retry "$CURL_RETRIES" --write-out '\n%{http_code}' )
[ -n "${MONITOR_CACERT-}" ] && curl_args+=( --cacert "$MONITOR_CACERT" )
response="$(curl "${curl_args[@]}" "$MONITOR_URL" 2>&1)"
curl_exit=$?
set -e

# Разбираем тело и http_code (последняя строка = код)
http_code="$(echo "$response" | tail -n1 || true)"
body="$(echo "$response" | sed '$d' || true)"

# Если curl упал (сетевые/SSL/DNS) — логируем ERROR
if [ "$curl_exit" -ne 0 ]; then
  echo "$(timestamp) ERROR: monitoring server unreachable, curl_exit=$curl_exit, body='${body:-}'" >> "$LOG_FILE"
  exit 0
fi

# Если http_code >= 400 — логируем ERROR
if [ -n "$http_code" ] && [ "$http_code" -ge 400 ]; then
  echo "$(timestamp) ERROR: monitoring server returned HTTP $http_code, body='${body:-}'" >> "$LOG_FILE"
  exit 0
fi

# Успех — по условию задания ничего не логируем
exit 0
