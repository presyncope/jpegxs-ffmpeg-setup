#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <target_dir>"
  exit 1
fi

dst_dir="$1"
backup_dir="$dst_dir/backup"

[[ -d "$dst_dir" ]]   || { echo "Target not found: $dst_dir" >&2; exit 1; }
[[ -d "$backup_dir" ]] || { echo "No backup directory: $backup_dir" >&2; exit 1; }

shopt -s nullglob

for file in "$backup_dir"/*; do
  [[ -e "$file" ]] || continue
  mv -f "$file" "$dst_dir/"
done

rmdir "$backup_dir" 2>/dev/null || :
echo "Restore completed: moved backups back to $dst_dir"
