#!/usr/bin/env bash
#
# Compress and prune rotated log files.
#
# Assumes something else already rotates daily, e.g. logrotate or the app writes
# app.log.2026-09-22 itself. This just gzips anything older than today and
# deletes gzips older than N days.
#
# Why not logrotate? logrotate is the right tool for system logs. But for app
# logs written by a process I don't control, a cron job that does the cleanup
# is less fuss than shipping a logrotate config.
#
# Usage:
#   ./rotate_logs.sh /var/log/myapp 30
#
set -euo pipefail

LOG_DIR="${1:-}"
RETENTION_DAYS="${2:-30}"

usage() {
    echo "usage: $(basename "$0") LOG_DIR [RETENTION_DAYS]" >&2
    echo "  LOG_DIR         directory containing *.log files" >&2
    echo "  RETENTION_DAYS  delete .gz older than this (default 30)" >&2
}

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

[[ -n "$LOG_DIR" ]] || { usage; exit 2; }
[[ -d "$LOG_DIR" ]] || { echo "no such directory: $LOG_DIR" >&2; exit 1; }
[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || { echo "RETENTION_DAYS must be a number" >&2; exit 2; }

# Refuse to operate on / or a top-level dir; a bad glob there would be ugly.
case "$LOG_DIR" in
    /|/bin|/etc|/usr|/var) echo "refusing to run on $LOG_DIR" >&2; exit 1 ;;
esac

shopt -s nullglob   # unmatched globs expand to nothing instead of the pattern

compressed=0
pruned=0

# 1. Compress yesterday-and-older .log files (anything not today's).
TODAY="$(date '+%Y-%m-%d')"
for f in "$LOG_DIR"/*.log.*; do
    # Skip today's still-being-written file and anything already compressed.
    case "$f" in
        *.gz) continue ;;
        *"$TODAY"*) continue ;;
    esac
    if gzip -9 -- "$f"; then
        compressed=$((compressed + 1))
    else
        log "WARN: gzip failed on $f, skipping"
    fi
done

# 2. Delete .gz files older than RETENTION_DAYS. -mtime +N means "modified more
#    than N*24h ago". Note +30 is strictly greater, so a file at exactly 30 days
#    survives one more day. That's fine, nobody cares about a one-day edge.
while IFS= read -r -d '' old; do
    rm -f -- "$old"
    pruned=$((pruned + 1))
done < <(find "$LOG_DIR" -maxdepth 1 -type f -name '*.gz' \
             -mtime "+${RETENTION_DAYS}" -print0)

log "compressed=$compressed pruned=$pruned dir=$LOG_DIR retention=${RETENTION_DAYS}d"

# 3. Warn if the dir is still getting large, so you notice before the disk fills.
TOTAL_MB="$(du -sm "$LOG_DIR" 2>/dev/null | cut -f1 || echo 0)"
if (( TOTAL_MB > 1024 )); then
    log "WARN: $LOG_DIR is ${TOTAL_MB} MB after rotation; check retention settings"
fi

exit 0
