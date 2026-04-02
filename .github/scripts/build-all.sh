#!/bin/sh
set -eu

# Per-package build orchestrator for CI.
# Calls `just build <pkg>` for each package, captures logs, continues on failure.
# Outputs via $GITHUB_OUTPUT: has_failures, failed_packages, succeeded_packages

mkdir -p /tmp/build-logs
: > /tmp/build-results.txt

failed=""
succeeded=""

for dir in packages/*/; do
    [ -f "$dir/PKGBUILD" ] || continue
    pkg=$(basename "$dir")
    echo "::group::Building $pkg"
    if just build "$pkg" > /tmp/build-logs/"$pkg".log 2>&1; then
        echo "pass $pkg" >> /tmp/build-results.txt
        succeeded="${succeeded:+$succeeded,}$pkg"
        echo "==> $pkg: OK"
    else
        echo "fail $pkg" >> /tmp/build-results.txt
        failed="${failed:+$failed,}$pkg"
        echo "::error::$pkg build failed"
    fi
    cat /tmp/build-logs/"$pkg".log
    echo "::endgroup::"
done

# Update repo database and clean old S3 packages
if [ -n "$succeeded" ]; then
    just repo-update
    for pkg in $(echo "$succeeded" | tr ',' ' '); do
        just s3-remove-old "$pkg"
    done
fi

# Write job summary
{
    echo "## Build Results"
    echo ""
    echo "| Package | Result |"
    echo "|---------|--------|"
    while IFS=' ' read -r status pkg; do
        if [ "$status" = "pass" ]; then
            echo "| $pkg | :white_check_mark: |"
        else
            echo "| $pkg | :x: |"
        fi
    done < /tmp/build-results.txt
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo "succeeded_packages=$succeeded" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "failed_packages=$failed" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ -n "$failed" ]; then
    echo "has_failures=true" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 1
else
    echo "has_failures=false" >> "${GITHUB_OUTPUT:-/dev/null}"
fi
