#!/bin/sh
set -eu

current="${1:?Usage: $0 <current_version>}"

# Get latest commit on master
commit=$(curl -s https://api.github.com/repos/Caellian/tree-sitter-glsl/commits/master \
  | grep -m1 '"sha"' | grep -oP '"sha":\s*"\K[^"]+')

# Get version from package.json at that commit
version=$(curl -s "https://raw.githubusercontent.com/Caellian/tree-sitter-glsl/$commit/package.json" \
  | grep -m1 '"version"' | grep -oP '"version":\s*"\K[^"]+')

[ -n "$version" ] || exit 0

# Get current commit from PKGBUILD
pkg_dir="$(dirname "$0")/../packages/tree-sitter-glsl"
current_commit=$(grep -m1 '^_commit=' "$pkg_dir/PKGBUILD" | cut -d= -f2)

# Report if version or commit changed
if [ "$version" != "$current" ] || [ "$commit" != "$current_commit" ]; then
  printf '{"version":"%s","tag":"stable","commit":"%s"}\n' "$version" "$commit"
fi
