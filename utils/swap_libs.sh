#!/usr/bin/env bash
set -euo pipefail

# 사용법 확인
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <source_dir> <target_dir>"
  exit 1
fi

src_dir="$1"
dst_dir="$2"
backup_dir="$dst_dir/backup"

# 디렉토리 존재 확인
[[ -d "$src_dir" ]] || { echo "Source not found: $src_dir" >&2; exit 1; }
[[ -d "$dst_dir" ]] || { echo "Target not found: $dst_dir" >&2; exit 1; }

mkdir -p "$backup_dir"
shopt -s nullglob

for src_path in "$src_dir"/*.so*; do
  [[ -e "$src_path" ]] || continue
  fname=$(basename "$src_path")
  base="${fname%%.so*}.so"   # ex: abcd.so.61 → abcd.so

  for old in "$dst_dir/$base"*; do
    [[ -e "$old" ]] || continue
    mv "$old" "$backup_dir/"
  done
  
  cp -a "$src_path" "$dst_dir/"
done
