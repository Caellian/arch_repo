#!/bin/sh
set -eu

# Usage: report-failure.sh <label> <package>
# Creates or updates a GitHub issue for a failed package build/patch.
#
# Environment variables (optional, for rich content):
#   BUILD_LOG_FILE  - path to build log file (for build-failure)
#   FAILED_PATCHES  - space-separated list of failed patch files (for patch-drift)
#   OLD_COMMIT      - old submodule commit hash (for patch-drift)
#   NEW_COMMIT      - new submodule commit hash (for patch-drift)
#   SUBMODULE_URL   - git URL for the submodule (for patch-drift commit links)

label="${1:?Usage: $0 <label> [package]}"
pkg="${2:-all}"
run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
template="$script_dir/../templates/$label.md"

# Prepare build log (truncated to stay under GitHub's 65536 char limit)
build_log=""
if [ -n "${BUILD_LOG_FILE:-}" ] && [ -f "$BUILD_LOG_FILE" ]; then
    build_log=$(tail -c 60000 "$BUILD_LOG_FILE")
fi

# Prepare patch list as markdown bullets
patch_list=""
if [ -n "${FAILED_PATCHES:-}" ]; then
    for p in $FAILED_PATCHES; do
        patch_list="${patch_list}- \`$p\`
"
    done
fi

# Prepare commit range link
commit_range=""
if [ -n "${OLD_COMMIT:-}" ] && [ -n "${NEW_COMMIT:-}" ] && [ -n "${SUBMODULE_URL:-}" ]; then
    old_short=$(echo "$OLD_COMMIT" | cut -c1-7)
    new_short=$(echo "$NEW_COMMIT" | cut -c1-7)
    # Derive cgit URL from AUR git URL
    # https://aur.archlinux.org/<pkg>.git -> https://aur.archlinux.org/cgit/aur.git/commit/?h=<pkg>&id=
    aur_pkg=$(echo "$SUBMODULE_URL" | sed 's|.*/||; s|\.git$||')
    base_url="https://aur.archlinux.org/cgit/aur.git/commit/?h=${aur_pkg}&id="
    commit_range="[${old_short}](${base_url}${OLD_COMMIT})..[${new_short}](${base_url}${NEW_COMMIT})"
fi

# Render template: simple vars with sed, then build_log with awk (handles multiline)
rendered=$(sed \
    -e "s|{{package}}|$pkg|g" \
    -e "s|{{date}}|$(date -u +%Y-%m-%d)|g" \
    -e "s|{{run_id}}|$GITHUB_RUN_ID|g" \
    -e "s|{{run_url}}|$run_url|g" \
    -e "s|{{commit_range}}|$commit_range|g" \
    "$template")

# Replace patch_list (may contain newlines)
rendered=$(echo "$rendered" | awk -v replacement="$patch_list" '{
    if (index($0, "{{patch_list}}")) {
        sub(/\{\{patch_list\}\}/, replacement)
    }
    print
}')

# Replace build_log using file directly (too large for awk -v)
if [ -n "$build_log" ]; then
    log_file=$(mktemp)
    echo "$build_log" > "$log_file"
    rendered=$(echo "$rendered" | awk -v logfile="$log_file" '{
        if (index($0, "{{build_log}}")) {
            while ((getline line < logfile) > 0) print line
            close(logfile)
        } else {
            print
        }
    }')
    rm -f "$log_file"
else
    rendered=$(echo "$rendered" | sed 's|{{build_log}}|No log captured.|g')
fi

# Extract title from frontmatter and body after it
title=$(echo "$rendered" | sed -n 's/^title: *"\(.*\)"/\1/p')
body=$(echo "$rendered" | sed '1,/^---$/{ /^---$/!d; d; }')

# Check for existing open issue
existing=$(gh issue list --state open --label "$label" --search "$pkg" --json number --jq '.[0].number // empty')

if [ -n "$existing" ]; then
    gh issue comment "$existing" --body "$body"
    echo "==> Updated issue #$existing"
else
    gh issue create --title "$title" --body "$body" --label "$label"
    echo "==> Created new issue"
fi
