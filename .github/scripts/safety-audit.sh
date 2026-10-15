#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
if ! repo_root="$(cd "$repo_root" && pwd)"; then
    printf 'safety audit: repository root does not exist: %s\n' "$repo_root" >&2
    exit 2
fi

source_root="$repo_root/Sources"
if [[ ! -d "$source_root" ]]; then
    printf 'safety audit: source directory does not exist: %s\n' "$source_root" >&2
    exit 2
fi

forbidden_pattern='(removeItem|trashItem|unlink(at)?|rmdir)[[:space:]]*\(|(^|[^.[:alnum:]_])remove[[:space:]]*\(|(system|popen|execl|execv|posix_spawn)[[:space:]]*\([^)]*(/bin/)?rm|(^|[^[:alnum:]_])rm("|[[:space:],]|$)'
violations=0

while IFS= read -r -d '' file; do
    relative_path="${file#"$repo_root"/}"
    case "$relative_path" in
        Sources/CoreKit/Safety/*)
            continue
            ;;
    esac

    if matches="$(grep -nE "$forbidden_pattern" "$file")"; then
        while IFS= read -r match; do
            printf '%s:%s\n' "$relative_path" "$match" >&2
        done <<< "$matches"
        violations=1
    else
        grep_status=$?
        if [[ "$grep_status" -ne 1 ]]; then
            printf 'safety audit: failed to scan %s\n' "$relative_path" >&2
            exit 2
        fi
    fi
done < <(find "$source_root" -type f -name '*.swift' -print0)

if [[ "$violations" -ne 0 ]]; then
    printf 'safety audit: file-deletion calls are only permitted in Sources/CoreKit/Safety/.\n' >&2
    exit 1
fi

printf 'safety audit: no forbidden file-deletion calls found outside Sources/CoreKit/Safety/.\n'
