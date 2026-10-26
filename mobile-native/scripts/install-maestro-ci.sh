#!/usr/bin/env bash
set -euo pipefail

# Only ephemeral CI runners; never install SDKs/tools on Gabrielle's Mac here.
[[ "${GITHUB_ACTIONS:-}" == "true" ]] || { echo 'Ce script est réservé à GitHub Actions.' >&2; exit 1; }
: "${RUNNER_TEMP:?}"
: "${GITHUB_PATH:?}"

maestro_version='2.12.0'
maestro_sha256='a6044a84542f522f434c5dc3d609e60c7446d423f3ed1b2ae513f5c48663ec5e'
maestro_dir="$RUNNER_TEMP/jolene-maestro-$maestro_version"
mkdir -p "$maestro_dir"
curl --proto '=https' --tlsv1.2 --fail --location --retry 3 --connect-timeout 20 --max-time 480 \
  "https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$maestro_version/maestro.zip" \
  --output "$maestro_dir/maestro.zip"
printf '%s  %s\n' "$maestro_sha256" "$maestro_dir/maestro.zip" | shasum -a 256 --check
unzip -q -o "$maestro_dir/maestro.zip" -d "$maestro_dir"
test -f "$maestro_dir/maestro/bin/maestro"
chmod +x "$maestro_dir/maestro/bin/maestro"
printf '%s\n' "$maestro_dir/maestro/bin" >> "$GITHUB_PATH"
