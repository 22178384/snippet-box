#!/usr/bin/env bash
# 简单备份：backup.sh <源目录> <目标目录>
set -euo pipefail
src="${1:?用法: backup.sh <源> <目标>}"
dst="${2:?}"
ts="$(date +%Y%m%d-%H%M%S)"
tar -czf "$dst/backup-$ts.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"
echo "已备份到 $dst/backup-$ts.tar.gz"
