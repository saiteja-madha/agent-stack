#!/usr/bin/env bash
# Read-only version audit. It does not refresh APT metadata or install updates.
set -u
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT

extract_version() {
  grep -oE 'v?[0-9]+(\.[0-9]+)+' | head -1 | sed 's/^v//'
}

version_status() {
  local installed=$1 latest=$2
  if [ -z "$installed" ] || [ -z "$latest" ] || [ "$latest" = unavailable ]; then
    printf 'unknown'
  elif [ "$installed" = "$latest" ]; then
    printf 'current'
  elif dpkg --compare-versions "$installed" lt "$latest" 2>/dev/null; then
    printf 'update available'
  else
    printf 'installed newer or versions differ'
  fi
}

installed_from_command() {
  local output
  output=$("$@" 2>/dev/null | head -1 || true)
  printf '%s' "$output" | extract_version
}

github_latest() {
  local repo=$1 major=${2:-}
  local file="$CHECK_DIR/${repo//\//_}.json" json
  [ -s "$file" ] || return 1
  json=$(cat "$file")
  if [ -n "$major" ]; then
    printf '%s' "$json" | jq -r --arg prefix "v$major." \
      '[.[] | select(.draft == false and .prerelease == false and (.tag_name | startswith($prefix) or startswith($prefix[1:])))] | .[0].tag_name // empty' 2>/dev/null
  else
    printf '%s' "$json" | jq -r '[.[] | select(.draft == false and .prerelease == false)][0].tag_name // empty' 2>/dev/null
  fi
}

github_latest_tag() {
  local repo=$1 major=$2
  local file="$CHECK_DIR/${repo//\//_}-tags.json"
  [ -s "$file" ] || return 1
  jq -r --arg prefix "v$major." \
    '[.[].name | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$") and (startswith($prefix) or startswith($prefix[1:]))) ] | sort_by(sub("^v"; "") | split(".") | map(tonumber)) | last // empty' \
    "$file" 2>/dev/null
}

node_latest_24() {
  [ -s "$CHECK_DIR/node-index.json" ] || return 1
  jq -r '[.[] | select(.version | startswith("v24."))][0].version // empty' \
    "$CHECK_DIR/node-index.json" 2>/dev/null | sed 's/^v//'
}

fetch_release_list() {
  local repo=$1
  local file="$CHECK_DIR/${repo//\//_}.json"
  curl -fsSL --connect-timeout 5 --max-time 15 \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$repo/releases?per_page=100" \
    -o "$file" 2>/dev/null || : > "$file"
}

fetch_opencode_tags() {
  curl -fsSL --connect-timeout 5 --max-time 15 \
    -H 'Accept: application/vnd.github+json' \
    'https://api.github.com/repos/anomalyco/opencode/tags?per_page=100' \
    -o "$CHECK_DIR/anomalyco_opencode-tags.json" 2>/dev/null \
    || : > "$CHECK_DIR/anomalyco_opencode-tags.json"
}

fetch_node_index() {
  curl -fsSL --connect-timeout 5 --max-time 15 https://nodejs.org/dist/index.json \
    -o "$CHECK_DIR/node-index.json" 2>/dev/null || : > "$CHECK_DIR/node-index.json"
}

for repo in pnpm/pnpm astral-sh/uv openai/codex \
  coder/code-server tailscale/tailscale cloudflare/cloudflared pingdotgg/t3code cli/cli NousResearch/hermes-agent saiteja-madha/bwenv; do
  fetch_release_list "$repo" &
done
fetch_opencode_tags &
fetch_node_index &
wait

report_release() {
  local name=$1 installed=$2 repo=$3 major=${4:-} latest
  latest=$(github_latest "$repo" "$major" | extract_version)
  if [ -z "$latest" ]; then latest=unavailable; fi
  printf '%-16s installed=%-14s upstream=%-14s status=%s\n' \
    "$name" "${installed:-unknown}" "$latest" \
    "$(version_status "$installed" "$latest")"
}

report_apt() {
  local name=$1 package=$2 output installed candidate status
  output=$(apt-cache policy "$package" 2>/dev/null || true)
  installed=$(printf '%s\n' "$output" | awk '/Installed:/ {print $2; exit}')
  candidate=$(printf '%s\n' "$output" | awk '/Candidate:/ {print $2; exit}')
  [ "$installed" = '(none)' ] && installed='not installed'
  [ "$candidate" = '(none)' ] && candidate='unavailable'
  if [ "$installed" = "$candidate" ]; then
    status=current
  elif [ "$candidate" = unavailable ] || [ "$installed" = 'not installed' ]; then
    status=unknown
  elif dpkg --compare-versions "$installed" lt "$candidate" 2>/dev/null; then
    status='update available'
  else
    status='installed newer or versions differ'
  fi
  printf '%-16s package=%-22s installed=%-32s candidate=%-32s status=%s\n' \
    "$name" "$package" "$installed" "$candidate" "$status"
}

echo 'Read-only update check; no APT refresh, installs, or service restarts are performed.'
echo 'APT candidates use the local package index and may be stale.'
echo
echo '--- Upstream stable releases ---'
node_installed=$(node --version 2>/dev/null | sed 's/^v//' || true)
node_latest=$(node_latest_24 || true)
printf '%-16s installed=%-14s upstream=%-14s status=%s\n' \
  Node "${node_installed:-unknown}" "${node_latest:-unavailable}" \
  "$(version_status "$node_installed" "$node_latest")"
report_release pnpm "$(pnpm --version 2>/dev/null || true)" pnpm/pnpm 12
report_release uv "$(installed_from_command uv --version)" astral-sh/uv
opencode_installed=$(installed_from_command opencode --version)
opencode_latest=$(github_latest_tag anomalyco/opencode 2 | extract_version)
if [ -z "$opencode_latest" ]; then opencode_latest=unavailable; fi
printf '%-16s installed=%-14s upstream=%-14s status=%s\n' \
  OpenCode "${opencode_installed:-unknown}" "$opencode_latest" \
  "$(version_status "$opencode_installed" "$opencode_latest")"
report_release Codex "$(installed_from_command codex --version)" openai/codex
report_release code-server "$(installed_from_command code-server --version)" coder/code-server
report_release Tailscale "$(installed_from_command tailscale version)" tailscale/tailscale
report_release cloudflared "$(installed_from_command cloudflared --version)" cloudflare/cloudflared
report_release T3-Code "$(installed_from_command t3 --version)" pingdotgg/t3code
report_release GitHub-CLI "$(installed_from_command gh --version)" cli/cli
report_release Hermes "$(installed_from_command hermes --version)" NousResearch/hermes-agent
report_release bwenv "$(installed_from_command bwenv --version)" saiteja-madha/bwenv
bws_installed=$(installed_from_command bws --version)
printf 'bws installed=%s; compare against the recorded official Bitwarden SDK bws release (SDK tags are not CLI versions).\n' "${bws_installed:-unknown}"

echo
echo '--- Configured APT package candidates ---'
report_apt Git git
report_apt GitHub-CLI gh
report_apt Docker docker-ce
report_apt Compose docker-compose-plugin
report_apt code-server code-server
report_apt Tailscale tailscale
report_apt cloudflared cloudflared

echo
echo '--- Managed Python interpreters ---'
if command -v uv >/dev/null 2>&1; then
  uv python list --only-installed 2>/dev/null || true
else
  echo 'uv unavailable'
fi

echo
echo '--- Running container image references ---'
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker ps --format '{{.Names}}' 2>/dev/null | while read -r name; do
    image=$(docker inspect --format '{{.Config.Image}}' "$name" 2>/dev/null || true)
    case "$image" in
      *@sha256:*) status='digest-pinned' ;;
      *:latest|latest) status='WARNING: floating latest tag' ;;
      *) status='tag reference; digest is not pinned' ;;
    esac
    printf '%-28s %-55s %s\n' "$name" "$image" "$status"
  done
else
  echo 'Docker unavailable'
fi
