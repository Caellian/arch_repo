#!/bin/sh
set -eu

# Usage: s3-sync.sh <push|pull>
# Syncs local/ packages with S3.
# Requires: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION

bucket="s3://packages-794644791074-eu-central-1-an"
local_dir="$(git rev-parse --show-toplevel)/local"

mkdir -p "$local_dir"

case "${1:?Usage: $0 <push|pull>}" in
    pull)
        aws s3 sync "$bucket" "$local_dir" --exclude '*' --include '*.pkg.tar.zst' --include '*.db*' --include '*.files*'
        echo "==> Pulled packages from S3"
        ;;
    push)
        aws s3 sync "$local_dir" "$bucket" --exclude '*' --include '*.pkg.tar.zst' --include '*.db*' --include '*.files*'
        echo "==> Pushed packages to S3"
        ;;
    *)
        echo "Usage: $0 <push|pull>" >&2
        exit 1
        ;;
esac
