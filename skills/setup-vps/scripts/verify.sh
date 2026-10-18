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
  'npm:npm --version' \
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

section "LISTENERS"
if command -v ss >/dev/null 2>&1; then
  sudo ss -ltnp 2>/dev/null || ss -ltn 2>/dev/null || true
fi

section "EXPECTED PORTS"
for port in 4096 8080 8081; do
  printf 'port %-5s ' "$port"
  if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
    echo LISTENING
  else
    echo NOT-LISTENING
  fi
done

section "OPENCODE OWNERSHIP"
opencode_lines=$(pgrep -af '/opencode (serve|web)' 2>/dev/null || true)
if [ -n "$opencode_lines" ]; then
  printf '%s\n' "$opencode_lines"
  count=$(printf '%s\n' "$opencode_lines" | grep -c . || true)
  if [ "$count" -gt 1 ]; then
    echo "WARNING: more than one OpenCode serve/web process is running. Check service ownership."
  fi
else
  echo "No OpenCode serve/web process found."
fi

section "SERVICES"
printf 'code-server:       enabled='; status_cmd sudo -n systemctl is-enabled "code-server@$USER.service" | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active "code-server@$USER.service" | head -1
printf 'opencode:          enabled='; status_cmd sudo -n systemctl is-enabled opencode.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active opencode.service | head -1
printf 'cloudflared:       enabled='; status_cmd sudo -n systemctl is-enabled cloudflared.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active cloudflared.service | head -1
printf 'tailscaled:        enabled='; status_cmd sudo -n systemctl is-enabled tailscaled.service | head -1
printf '                   active=';  status_cmd sudo -n systemctl is-active tailscaled.service | head -1

section "CODE-SERVER CONFIG (SANITIZED)"
if [ -f "$HOME/.config/code-server/config.yaml" ]; then
  grep -vE '^[[:space:]]*(password|hashed-password):' "$HOME/.config/code-server/config.yaml" || true
else
  echo "No config found."
fi

section "TAILSCALE"
cmd tailscale status
printf '\n--- Preferences (selected) ---\n'
cmd tailscale debug prefs | grep -E '"(RunSSH|CorpDNS|ShieldsUp|AdvertiseRoutes|RouteAll|ExitNodeID|AutoUpdate)"' || true
printf '\n--- Serve ---\n'
cmd tailscale serve status
printf '\n--- Funnel ---\n'
cmd tailscale funnel status

section "FIREWALL"
cmd sudo ufw status verbose

section "SSH EFFECTIVE SETTINGS"
cmd sudo sshd -T | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|allowgroups|maxauthtries|x11forwarding) '

section "PUBLIC EXPOSURE CHECK"
if sudo ss -ltnup 2>/dev/null | grep -Eq '0\.0\.0\.0:|\[::\]:'; then
  sudo ss -ltnup 2>/dev/null | grep -E '0\.0\.0\.0:|\[::\]:' || true
else
  echo "No wildcard listeners detected."
fi
echo "Expected application bindings: 127.0.0.1:4096, 127.0.0.1:8080, 127.0.0.1:8081."

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
printf '\n--- volumes ---\n'
cmd docker volume ls
printf '\n--- networks ---\n'
cmd docker network ls
printf '\n--- disk usage ---\n'
cmd docker system df
printf '\n--- swarm ---\n'
cmd docker info --format 'Swarm state: {{.Swarm.LocalNodeState}}'

section "NOTES"
echo "Expected local services: OpenCode :4096, code-server :8080, Excalidraw :8081."
echo "Review any listener on 0.0.0.0/[::] and any Tailscale output not marked tailnet-only."
echo "This script intentionally does not print credentials, Cloudflare tunnel tokens, or .env files."
