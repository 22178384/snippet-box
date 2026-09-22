#!/usr/bin/env bash
#
# Timestamped rsync backup with rotation and a lock file.
#
# I wrote this after cron ran two copies at once during a DST change and I ended
# up with two half-backups fighting over the same directory. The flock is not
# optional if you schedule this.
#
# Usage:
#   ./backup.sh -s /srv/data -d /mnt/backups -k 7
#   ./backup.sh --help
#
set -euo pipefail

# Run, don't source. `set -euo pipefail` above would leak into your shell.

SRC=""
DEST=""
KEEP=7
LOCKFILE="/tmp/backup.lock"

usage() {
    cat <<'EOF'
backup.sh - rsync a directory into a timestamped snapshot and prune old ones.

  -s, --src DIR      source directory (required)
  -d, --dest DIR     destination root; snapshots land in DEST/hostname/ (required)
  -k, --keep N       how many snapshots to keep (default: 7)
  -h, --help         this message
EOF
}

log() {
    # ISO-ish timestamp without calling out to `date` twice.
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--src)  SRC="${2:-}"; shift 2 ;;
        -d|--dest) DEST="${2:-}"; shift 2 ;;
        -k|--keep) KEEP="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ -n "$SRC"  ]] || die "missing --src"
[[ -n "$DEST" ]] || die "missing --dest"
[[ -d "$SRC"  ]] || die "source does not exist: $SRC"
[[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep must be a number, got: $KEEP"

# --- lock ---------------------------------------------------------------
# fd 9 holds the lock for the lifetime of the script. If another instance is
# running, -n makes flock fail immediately instead of queueing up.
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    die "another backup is already running (lock: $LOCKFILE)"
fi

# --- backup -------------------------------------------------------------
HOSTNAME_SHORT="$(hostname -s 2>/dev/null || hostname)"
STAMP="$(date '+%Y%m%d-%H%M%S')"
TARGET_ROOT="${DEST}/${HOSTNAME_SHORT}"
TARGET="${TARGET_ROOT}/${STAMP}"

mkdir -p "$TARGET"

log "starting backup: $SRC -> $TARGET"

# --link-dest hard-links unchanged files to the previous snapshot, so ten
# snapshots don't cost ten times the disk. Falls back to a full copy for the
# first run. -a preserves perms/times/symlinks; --delete keeps it a mirror.
LATEST_LINK="${TARGET_ROOT}/latest"
LINK_ARGS=()
if [[ -d "$LATEST_LINK" ]]; then
    LINK_ARGS=(--link-dest="$LATEST_LINK")
fi

rsync -a --delete --partial --human-readable "${LINK_ARGS[@]}" \
    --exclude='.cache/' \
    --exclude='*.tmp' \
    "$SRC/" "$TARGET/"

# Repoint `latest` at the new snapshot (symlink swap is atomic-ish).
ln -sfn "$TARGET" "${TARGET_ROOT}/latest.new"
mv -Tf "${TARGET_ROOT}/latest.new" "$LATEST_LINK" 2>/dev/null \
    || ln -sfn "$TARGET" "$LATEST_LINK"

log "backup done: $TARGET"

# --- rotate -------------------------------------------------------------
# List snapshots newest-first, drop the ones past $KEEP. `|| true` because
# `ls` exits non-zero when nothing matches, and with `set -e` that would abort.
mapfile -t SNAPSHOTS < <(ls -1dt "${TARGET_ROOT}"/*/ 2>/dev/null || true)

if (( ${#SNAPSHOTS[@]} > KEEP )); then
    for old in "${SNAPSHOTS[@]:KEEP}"; do
        log "pruning old snapshot: $old"
        rm -rf -- "$old"
    done
fi

log "kept $KEEP snapshot(s) under $TARGET_ROOT"
exit 0
