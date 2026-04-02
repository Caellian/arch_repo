#!/bin/sh
set -eu

current="${1:?Usage: $0 <current_version>}"

curl -s https://foundryvtt.com/releases/ \
  | awk '
    /href="\/releases\/[0-9]/ { match($0, /releases\/([0-9]+\.[0-9]+)/, m); ver=m[1] }
    /release-tag">Full</ { full=1 }
    /release-tag [a-z]/ { if (full) { match($0, /release-tag ([a-z]+)/, m); tag=m[1]; print ver, tag; full=0 } }
  ' \
  | while read -r ver tag; do
    if [ "$(printf '%s\n%s' "$current" "$ver" | sort -V | head -1)" = "$current" ] && [ "$ver" != "$current" ]; then
      printf '{"version":"%s","tag":"%s","notes":"https://foundryvtt.com/releases/%s"}\n' "$ver" "$tag" "$ver"
    fi
  done
