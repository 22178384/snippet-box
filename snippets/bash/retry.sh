#!/usr/bin/env bash
# 失败自动重试。用法：retry.sh <次数> <命令...>
set -euo pipefail
n="${1:?用法: retry.sh <次数> <命令>}"
shift
for i in $(seq 1 "$n"); do
  if "$@"; then
    echo "成功（第 $i 次）"; exit 0
  fi
  echo "第 $i 次失败，重试…"
done
echo "已重试 $n 次仍失败"; exit 1
