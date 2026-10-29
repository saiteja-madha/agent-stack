#!/usr/bin/env bash
set -u

section() { printf '\n===== %s =====\n' "$1"; }
cmd() { "$@" 2>/dev/null || true; }

# Make the user systemd manager reachable from non-interactive SSH/agent shells
# when its runtime bus exists, without prompting for credentials.
user_uid=$(id -u)
if [ -S "/run/user/$user_uid/bus" ]; then
  export XDG_RUNTIME_DIR="/run/user/$user_uid"
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$user_uid/bus"
fi

status_cmd() {
  local output
  if ! output=$("$@" 2>/dev/null); then
    echo "[unavailable]"
  elif [ -n "$output" ]; then
    printf '%s\n' "$output"
  else
    echo "[unavailable]"
  fi
}

section "OS / HOST"
cmd grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
cmd uname -srmo
cmd hostname

section "USER / PERSISTENCE"
id
printf 'shell=%s\n' "${SHELL:-unknown}"
printf 'home=%s\n' "${HOME:-unknown}"
cmd loginctl show-user "$USER" -p Linger

section "TOOLCHAIN"
for spec in \
  'node:node --version' \
  'pnpm:pnpm --version' \
  'uv:uv --version' \
  'git:git --version' \
  'python3:python3 --version' \
  'docker:docker --version' \
  'opencode:opencode --version' \
  'codex:codex --version' \
  'code-server:code-server --version' \
  'tailscale:tailscale version' \
  'cloudflared:cloudflared --version'
do
  name=${spec%%:*}
  command=${spec#*:}
  printf '%-14s ' "$name"
  bash -lc "$command" 2>/dev/null | head -1 || true
done
printf '\n--- executable paths ---\n'
for tool in node pnpm codex opencode cloudflared; do
  printf '%-14s ' "$tool"
  command -v "$tool" 2>/dev/null || echo '[missing]'
done

section "LISTENERS"
if command -v ss >/dev/null 2>&1; then
  sudo ss -ltnp 2>/dev/null || ss -ltn 2>/dev/null || true
fi

section "EXPECTED PORTS"
for port in 80 3773 4096 8080 8081; do
  printf 'port %-5s ' "$port"
  if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
    echo LISTENING
  else
    echo NOT-LISTENING
  fi
done

section "OPENCODE OWNERSHIP"
count=0
for pid in $(pgrep -x opencode 2>/dev/null || true); do
  [ -r "/proc/$pid/cmdline" ] || continue
  process_cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline")
  case "$process_cmd" in
    *" serve "*) role=serve ;;
    *" web "*) role=web ;;
    *) continue ;;
  esac
  count=$((count + 1))
  ppid=$(awk '/^PPid:/ {print $2}' "/proc/$pid/status")
  parent=$(ps -p "$ppid" -o comm= 2>/dev/null | xargs || true)
  printf 'pid=%s role=%s user=%s ppid=%s parent=%s elapsed=%s\n' \
    "$pid" "$role" "$(ps -p "$pid" -o user= | xargs)" "$ppid" \
    "${parent:-unknown}" "$(ps -p "$pid" -o etime= | xargs)"
  printf '  cgroup: '
  tr '\n' ' ' <"/proc/$pid/cgroup" 2>/dev/null || true
  printf '\n'
done
if [ "$count" -gt 1 ]; then
  echo "WARNING: multiple OpenCode serve/web processes found; use parent and cgroup data to identify their owners."
elif [ "$count" -eq 0 ]; then
  echo "No OpenCode serve/web process found."
else
  echo "One OpenCode serve/web process found."
fi

section "SERVICES"
printf 'traefik:           '; status_cmd sudo -n docker inspect -f '{{.State.Status}}' traefik | head -1
printf 'code-server:       enabled='; status_cmd sudo -n systemctl is-enabled "code-server@$USER.service" | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active "code-server@$USER.service" | head -1
printf 'opencode:          enabled='; status_cmd sudo -n systemctl is-enabled opencode.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active opencode.service | head -1
printf 't3code:            enabled='; status_cmd systemctl --user is-enabled t3code.service | head -1
printf '                   active=';  status_cmd systemctl --user is-active t3code.service | head -1
printf 'cloudflared:       enabled='; status_cmd sudo -n systemctl is-enabled cloudflared.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active cloudflared.service | head -1
printf 'tailscaled:        enabled='; status_cmd sudo -n systemctl is-enabled tailscaled.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active tailscaled.service | head -1
printf 'docker:            enabled='; status_cmd sudo -n systemctl is-enabled docker.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active docker.service | head -1

section "SYSTEM HEALTH"
printf '%s\n' '--- failed units ---'
cmd systemctl --failed --no-legend
printf '%s\n' '--- reboot state ---'
if [ -f /var/run/reboot-required ]; then
  echo 'REBOOT REQUIRED'
  cmd sed -n '1,40p' /var/run/reboot-required.pkgs
else
  echo 'No reboot required.'
fi
printf '%s\n' '--- Cockpit must be absent ---'
if systemctl list-unit-files cockpit.socket --no-legend 2>/dev/null | grep -q cockpit.socket; then
  echo 'WARNING: cockpit.socket is installed.'
else
  echo 'Cockpit is absent.'
fi

section "CODE-SERVER CONFIG (SANITIZED)"
if [ -f "$HOME/.config/code-server/config.yaml" ]; then
  grep -vE '^[[:space:]]*(password|hashed-password):' "$HOME/.config/code-server/config.yaml" || true
else
  echo "No config found."
fi

section "TAILSCALE"
cmd tailscale status
printf '\n--- Preferences (selected) ---\n'
cmd tailscale debug prefs | grep -E '"(RunSSH|CorpDNS|ShieldsUp|AdvertiseRoutes|AdvertiseServices|RouteAll|ExitNodeID|AutoUpdate)"' || true
printf '\n--- Serve ---\n'
cmd tailscale serve status
printf '\n--- Funnel ---\n'
cmd tailscale funnel status
printf '\n--- Named service host ---\n'
cmd tailscale status --json | jq '.Self | {Tags, ServiceHost: (.CapMap["service-host"] // null)}' || true
printf '\n--- Expected advertised services ---\n'
service_host_json=$(tailscale status --json 2>/dev/null | jq -r '.Self.CapMap["service-host"][0] // {} | keys[]' 2>/dev/null || true)
for service in svc:draw svc:code svc:opencode svc:t3code; do
  if printf '%s\n' "$service_host_json" | grep -Fxq "$service"; then
    printf '%s advertised\n' "$service"
  else
    printf '%s NOT FOUND\n' "$service"
  fi
done

section "FIREWALL"
cmd sudo ufw status verbose

section "SSH EFFECTIVE SETTINGS"
ssh_effective=$(sudo sshd -T 2>/dev/null || true)
printf '%s\n' "$ssh_effective" | grep -E '^(port|listenaddress|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|allowgroups|maxauthtries|x11forwarding) '
ssh_listen_addresses=$(printf '%s\n' "$ssh_effective" | awk '$1 == "listenaddress" {print $2}' | sed -E 's/^\[([^]]+)\]:.*/\1/; s/:22$//')
tailscale_addresses=$( { tailscale ip -4 2>/dev/null; tailscale ip -6 2>/dev/null; } | sed '/^$/d')
for address in $tailscale_addresses; do
  if printf '%s\n' "$ssh_listen_addresses" | grep -Fxq "$address"; then
    printf 'SSH bound to Tailscale address %s\n' "$address"
  else
    printf 'WARNING: SSH is not bound to Tailscale address %s\n' "$address"
  fi
done
for address in $ssh_listen_addresses; do
  if printf '%s\n' "$tailscale_addresses" | grep -Fxq "$address"; then
    :
  else
    printf 'WARNING: SSH listens on non-Tailscale address %s\n' "$address"
  fi
done

section "WILDCARD LISTENERS (INTERFACE BINDINGS)"
wildcard_listeners=$(sudo ss -H -ltnup 2>/dev/null | awk '$5 ~ /^(0\.0\.0\.0:|\[::\]:|\*:)/ {print}' || true)
if [ -n "$wildcard_listeners" ]; then
  printf '%s\n' "$wildcard_listeners"
else
  echo "No wildcard listeners detected."
fi
echo "Expected application bindings: 127.0.0.1:80 (Traefik), 127.0.0.1:3773 (T3 Code), 127.0.0.1:4096 (OpenCode), 127.0.0.1:8080 (code-server), 127.0.0.1:8081 (Excalidraw)."
echo "SSH should bind only to the VPS Tailscale addresses; UFW should permit inbound SSH only on tailscale0."
echo "Listener bindings do not establish public internet reachability; also inspect provider firewall rules or test from outside the VPS."

section "SECURITY SERVICES"
printf 'fail2ban='; cmd systemctl is-active fail2ban | head -1
printf 'unattended-upgrades='; cmd systemctl is-enabled unattended-upgrades | head -1

section "DOCKER"
cmd docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
printf '\n--- restart policies ---\n'
cmd docker ps -a --format '{{.Names}}' | while read -r container; do
  [ -n "$container" ] || continue
  printf '%s: ' "$container"
  docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$container" 2>/dev/null || true
done
printf '\n--- compose ownership ---\n'
cmd docker ps -a --format '{{.Names}}' | while read -r container; do
  [ -n "$container" ] || continue
  docker inspect -f '{{.Name}} project={{index .Config.Labels "com.docker.compose.project"}} files={{index .Config.Labels "com.docker.compose.project.config_files"}}' "$container" 2>/dev/null || true
done
printf '\n--- volumes ---\n'
cmd docker volume ls
printf '\n--- networks ---\n'
cmd docker network ls
printf '\n--- disk usage ---\n'
cmd docker system df
printf '\n--- swarm ---\n'
cmd docker info --format 'Swarm state: {{.Swarm.LocalNodeState}}'

section "NOTES"
echo "Expected local services: Traefik :80, T3 Code :3773, OpenCode :4096, code-server :8080, Excalidraw :8081."
echo "Review any listener on 0.0.0.0/[::] and any Tailscale output not marked tailnet-only."
echo "This script intentionally does not print credentials, Cloudflare tunnel tokens, or .env files."
