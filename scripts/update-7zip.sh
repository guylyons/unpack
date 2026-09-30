#!/bin/zsh
# Replace the bundled 7-Zip with a release from 7-zip.org.
# Usage: scripts/update-7zip.sh 2603   (the version without the dot, e.g. 26.03 → 2603)
set -euo pipefail

version=${1:?"usage: $0 <version, e.g. 2603>"}
root=${0:A:h:h}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "https://www.7-zip.org/a/7z${version}-mac.tar.xz" | tar -xJ -C "$tmp"
cp "$tmp/7zz" "$tmp/License.txt" "$tmp/readme.txt" "$root/Vendor/7zip/"
"$root/Vendor/7zip/7zz" | head -2 | tail -1
