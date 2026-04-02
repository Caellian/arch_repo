#!/bin/sh
set -eu

# Per-package build orchestrator for CI.
# Calls `just build <pkg>` for each package, captures logs, continues on failure.
# Outputs via $GITHUB_OUTPUT: has_failures, failed_packages, succeeded_packages

s3_remove_old() {
    pkg="$1"
    pkgname=$(grep -m1 '^pkgname=' "packages/$pkg/PKGBUILD" | cut -d= -f2)
    current=$(ls "$REPO_DIR"/${pkgname}-*.pkg.tar.zst 2>/dev/null | head -1)
    [ -n "$current" ] || return 0
    current_base=$(basename "$current")
    bucket_name=$(echo "$S3_BUCKET" | sed 's,s3://,,')
    aws s3api list-objects-v2 --bucket "$bucket_name" \
        --prefix "${pkgname}-" --query "Contents[].Key" --output text \
    | tr '\t' '\n' \
    | grep '\.pkg\.tar\.zst$' \
    | while read -r key; do
        if [ "$(basename "$key")" != "$current_base" ]; then
            echo "==> Removing old package: $key"
            aws s3 rm "$S3_BUCKET/$key"
        fi
    done
}

mkdir -p /tmp/build-logs
: > /tmp/build-results.txt

failed=""
succeeded=""

for dir in packages/*/; do
    [ -f "$dir/PKGBUILD" ] || continue
    pkg=$(basename "$dir")
    echo "::group::Building $pkg"
    if just build "$pkg" > /tmp/build-logs/"$pkg".log 2>&1; then
        if grep -q '==> Skipping' /tmp/build-logs/"$pkg".log; then
            echo "skip $pkg" >> /tmp/build-results.txt
            echo "==> $pkg: skipped"
        else
            echo "pass $pkg" >> /tmp/build-results.txt
            succeeded="${succeeded:+$succeeded,}$pkg"
            echo "==> $pkg: OK"
            # Push immediately so progress isn't lost on timeout
            just repo-update "$pkg"
            s3_remove_old "$pkg"
            just push
        fi
    else
        echo "fail $pkg" >> /tmp/build-results.txt
        failed="${failed:+$failed,}$pkg"
        echo "::error::$pkg build failed"
    fi
    cat /tmp/build-logs/"$pkg".log
    echo "::endgroup::"
done

# Write job summary
{
    echo "## Build Results"
    echo ""
    echo "| Package | Result |"
    echo "|---------|--------|"
    while IFS=' ' read -r status pkg; do
        case "$status" in
            pass) echo "| $pkg | :white_check_mark: |" ;;
            skip) echo "| $pkg | :fast_forward: skipped |" ;;
            fail) echo "| $pkg | :x: |" ;;
        esac
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
