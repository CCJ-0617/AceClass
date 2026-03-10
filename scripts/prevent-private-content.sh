#!/bin/sh
set -eu

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

files_list="$(mktemp)"
content_tmp="$(mktemp)"
matches_tmp="$(mktemp)"
trap 'rm -f "$files_list" "$content_tmp" "$matches_tmp"' EXIT

git diff --cached --name-only --diff-filter=ACMR > "$files_list"

if [ ! -s "$files_list" ]; then
    exit 0
fi

blocked=0
private_content_regex='-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|sk_live_[A-Za-z0-9]+|xox[baprs]-[A-Za-z0-9-]+|/Users/[^/[:space:]]+|/home/[^/[:space:]]+'

while IFS= read -r path; do
    [ -n "$path" ] || continue

    case "$path" in
        .specstory/.gitignore)
            continue
            ;;
        .githooks/pre-commit|scripts/prevent-private-content.sh)
            continue
            ;;
        .DS_Store|*/.DS_Store|*.xcuserstate|*.xccheckout|*.xcscmblueprint|*/xcuserdata/*|.env|.env.*|*.p12|*.mobileprovision|*.cer|*.key|*.pem|.specstory/*|*.log)
            echo "Blocked staged file: $path" >&2
            blocked=1
            continue
            ;;
    esac

    if ! git show ":$path" > "$content_tmp" 2>/dev/null; then
        continue
    fi

    if LC_ALL=C grep -Iq . "$content_tmp"; then
        if LC_ALL=C grep -nE -- "$private_content_regex" "$content_tmp" > "$matches_tmp"; then
            echo "Potential private content detected in staged file: $path" >&2
            sed -n '1,3p' "$matches_tmp" >&2
            blocked=1
        fi
    fi
done < "$files_list"

if [ "$blocked" -ne 0 ]; then
    cat >&2 <<'EOF'
Commit blocked to avoid submitting private or user-specific content.
If this is intentional, clean the staged changes and review them with:
  git diff --cached
EOF
    exit 1
fi
