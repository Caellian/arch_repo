#!/bin/sh
set -eu

# Per-package patch checker for CI.
# Dry-runs each patch, records which specific files drifted.
# Outputs via $GITHUB_OUTPUT: has_failures, failed_packages

patch_dir="patches"
pkg_dir="packages"

: > /tmp/patch-results.txt
failed=""

for dir in "$patch_dir"/*/; do
    [ -d "$dir" ] || continue
    pkg=$(basename "$dir")
    [ -d "$pkg_dir/$pkg" ] || continue

    failed_patches=""
    all_ok=true

    cd "$pkg_dir/$pkg"
    for p in "../../$patch_dir/$pkg"/*; do
        [ -f "$p" ] || continue
        name=$(basename "$p")
        # Only check .patch files that target existing files
        [ "${name%.patch}" != "$name" ] && [ -f "${name%.patch}" ] || continue
        if ! patch --dry-run -p1 < "$p" > /dev/null 2>&1; then
            failed_patches="${failed_patches:+$failed_patches }$name"
            all_ok=false
        fi
    done
    cd ../..

    if $all_ok; then
        echo "pass $pkg" >> /tmp/patch-results.txt
    else
        echo "fail $pkg $failed_patches" >> /tmp/patch-results.txt
        failed="${failed:+$failed,}$pkg"
    fi
done

# Write job summary
{
    echo "## Patch Check Results"
    echo ""
    echo "| Package | Result | Failed Patches |"
    echo "|---------|--------|----------------|"
    while IFS= read -r line; do
        status=$(echo "$line" | cut -d' ' -f1)
        pkg=$(echo "$line" | cut -d' ' -f2)
        patches=$(echo "$line" | cut -d' ' -f3-)
        if [ "$status" = "pass" ]; then
            echo "| $pkg | :white_check_mark: | — |"
        else
            echo "| $pkg | :x: | \`$patches\` |"
        fi
    done < /tmp/patch-results.txt
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "failed_packages=$failed" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ -n "$failed" ]; then
    echo "has_failures=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 1
else
    echo "has_failures=false" >> "${GITHUB_OUTPUT:-/dev/null}"
fi
