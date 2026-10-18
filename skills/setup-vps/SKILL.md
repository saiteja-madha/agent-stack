---
name: setup-vps
description: Audit, set up, and maintain a personal Ubuntu VPS for AI-assisted development using OpenCode, Codex CLI, code-server, Tailscale, Cloudflare Tunnel/Access, Docker, and Excalidraw. Use when provisioning or rebuilding the VPS, changing these services, checking exposure/firewall state, migrating workloads, or troubleshooting the AI development stack.
compatibility: Ubuntu/Debian VPS with bash, systemd, sudo, Docker, Tailscale, and Cloudflare Tunnel. Intended for a single-user AI development VPS.
---

# Setup VPS

Maintain a small, secure AI-development VPS. Prefer simple host-native developer tooling, localhost-only listeners, and explicit private/reverse-proxy access.

## Starting access policy

For a first-time setup, use `sunny` as the only interactive SSH administrator. Keep
SSH password authentication enabled because this installation intentionally uses a
password over the private Tailscale network. Disable root SSH login with
`PermitRootLogin no`; do not delete or lock the root account until recovery access
has been verified. Permit SSH only through `tailscale0`, remove public IPv4 and IPv6
SSH firewall rules, and keep `sunny` in the `sudo` group.

Before changing SSH or firewall access, keep the current session open and verify a
fresh `sunny` login over Tailscale. After the change, validate both `sshd -T` and
the firewall rules. Never disable password authentication unless the user explicitly
changes this policy.

## Tailscale policy

Keep the VPS named `homelab` in Tailscale. Tailscale is the only inbound network
for administration and development access. Use regular OpenSSH over the Tailscale
network with the `sunny` user and password authentication; do not use Tailscale SSH.
Keep root SSH disabled. Allow future devices on the tailnet to connect.

Keep MagicDNS and automatic Tailscale updates enabled. Keep Funnel disabled. Do not
use this VPS as an exit node, subnet router, or route acceptor. Before removing the
currently advertised `10.0.1.0/24` route, inspect the VPS and its current routes to
confirm it is no longer needed; apply its removal only after explicit approval.

Use Tailscale Serve for private HTTPS with separate MagicDNS names for code-server
and OpenCode. Keep OpenCode's own password authentication enabled as a second
security layer. code-server may use `auth: none` because it remains bound to
localhost and is reachable only through private Tailscale Serve; it must never be
publicly accessible. Neither service may be publicly accessible. Remove stale Serve
routes when their target service is retired. Verify Tailscale state automatically,
but apply configuration changes only after explicit approval.

## SSH and firewall policy

Keep SSH on port `22` with password authentication enabled. Enforce
`AllowUsers sunny` and `PermitRootLogin no`; retain the root account for local or
provider-console recovery. Allow SSH through `tailscale0` only. Keep application
ports bound to localhost by default, with exceptions requiring explicit approval.

Automate checks for public listeners and firewall exposure. Do not require fail2ban
for this Tailscale-only SSH design. Before any SSH or firewall change, keep the
current session open, obtain explicit approval, and require a successful fresh
`sunny` session over Tailscale before considering the change complete.

## Docker policy

Enable the Docker daemon at boot and configure containers to restart automatically.
Use Docker Compose as the standard deployment method. Bind all container ports to
localhost by default. Use exact image tags or digests, never floating application
tags. Do not automate volume backups yet. Require explicit approval for destructive
Docker actions, including removing containers, images, volumes, networks, or build
cache.

## Toolchain and update policy

Use pnpm 12 to manage Node.js 24.x LTS and project dependencies. Keep npm optional
and do not manage it separately unless a project requires it. Use uv at its latest
stable release to manage Python versions, environments, and dependencies. Keep the
Ubuntu system Python available for OS tooling; select and pin Python per project,
using the newest stable version supported by that project.

OpenCode, Codex CLI, code-server, Tailscale, and cloudflared track their latest
stable releases using their documented install sources. Docker Engine tracks the
stable current major through Docker's official APT repository; Docker Compose uses
the Docker Compose APT plugin and updates with Docker. Git tracks the latest Ubuntu
APT version. Ubuntu receives security updates only.

Maintenance will be a separate future command. Independent updates may run in
parallel, but each install or update must be verified afterward. Service restarts
require explicit approval. Preserve the previous version where possible and roll
back failed updates when the tool supports rollback; otherwise stop and report the
limitation. Keep cookbook procedures conceptual with minimal reproducible steps.

## Tool inventory

Maintain this table whenever the VPS is provisioned or updated. Pin application
versions and container images before installation. System utilities may explicitly
track the latest version from the configured Ubuntu OS repository when noted in the
table; do not use floating application or container tags such as `latest`.

| Tool | Desired version | Install source | Service/listener | Notes |
|---|---|---|---|---|
| Ubuntu | 22.04 LTS | Provider | apply security updates | |
| Git | latest | `apt` | Host | Intentionally tracks the latest configured OS repository version |
| Node.js | 24.x LTS | pnpm  `12` | Host | Use pnpm to manage the Node.js runtime |
| npm | Optional | Bundled with Node.js | Host | Do not manage separately unless a project requires it |
| pnpm | 12.x | Standalone installer | Host | Primary Node.js package manager and Node.js runtime manager |
| uv | Latest stable | Official installer | Host | Use uv for Python installation, environments, and dependencies |
| Python | Managed by uv | uv | Host | Install alongside system Python |
| Docker Engine | Stable, current major | Official Docker APT repository | Host service | Controlled APT upgrades |
| Docker Compose | Latest stable | Docker Compose APT plugin | Host | Update with Docker |
| Docker CLI | Update with Docker | Official Docker APT repository | Host CLI | Update with Docker |
| OpenCode | Latest stable | Official standalone installer | `127.0.0.1:4096` | Manual stable updates |
| Codex CLI | Latest stable | Official native installer | Host CLI | Manual stable updates |
| code-server | Latest stable | Official `.deb` installer | `127.0.0.1:8080` | Managed package updates |
| Tailscale | Latest stable | Official APT repository | Host service | Regular security updates |
| cloudflared | Latest stable | Official APT repository | Host service | Regular security updates |
| Excalidraw | TBD | Docker image | `127.0.0.1:8081` | Use an explicit version or digest, not `latest` |

The table records the desired version and installation method so a rebuild can be deterministic.

## Safety rules

- Start with a read-only audit. Run `scripts/verify.sh` before proposing changes.
- Never print, commit, or request API keys, OAuth tokens, Cloudflare tunnel tokens, passwords, private SSH keys, or `.env` contents.
- Do not run destructive Docker/system cleanup, remove volumes, uninstall software, alter firewall rules, or change SSH authentication without explicit user approval.
- Before deleting a service or volume, identify what owns it and whether persistent data has been backed up or migrated.
- Prefer exact service/container names over broad `pkill`, `docker system prune --volumes`, or similar blanket cleanup.
- Keep application ports on `127.0.0.1` unless there is a specific reason to expose them.
- Use Tailscale or Cloudflare Tunnel instead of opening application ports in the public firewall.

## Preferred architecture

Use this layout unless the user explicitly chooses otherwise:

```text
VPS host
├── OpenCode            127.0.0.1:4096
│   └── Cloudflare Access/Tunnel
├── Codex CLI           host-native, authenticated separately
├── code-server         127.0.0.1:8080
│   └── Cloudflare Access/Tunnel
├── cloudflared         host service
├── tailscaled          host service
└── Docker
    └── Excalidraw      127.0.0.1:8081 → Cloudflare Access/Tunnel
```

### OpenCode

- Use the host-native OpenCode CLI.
- Install OpenCode with the official user-local installer:

  ```bash
  curl -fsSL https://opencode.ai/install | bash
  ```

  The expected executable is `~/.opencode/bin/opencode`; do not replace this
  installation with apt, Homebrew, or a global npm package when reproducing this
  host. Verify with `command -v opencode`, `readlink -f "$(command -v opencode)"`,
  and `opencode --version`.
- Run exactly one OpenCode server on `127.0.0.1:4096` with
  `opencode serve --hostname 127.0.0.1 --port 4096`.
- Keep OpenCode's own authentication configured when its server is reachable through
  a reverse proxy; Cloudflare Access is an additional access layer.
- The local `~/.opencode/package.json` and `node_modules` are supporting plugin
  dependencies, not the CLI installation.
- See the [official OpenCode installation documentation](https://opencode.ai/en/docs)
  and [server documentation](https://opencode.ai/v2/docs/cli/web).

### Codex

- Install Codex CLI natively on the host.
- Authenticate Codex separately from OpenCode.
- Do not add OpenAI OAuth to OpenCode merely because Codex is installed; keep provider authentication independent when that is the user's preference.

### code-server

- Prefer native code-server for this AI-development VPS so the editor, agents, Git, Node, Python, SSH configuration, and repositories share the host environment.
- Run it as `code-server@<user>` and bind only to `127.0.0.1:8080`.
- `auth: none` is acceptable for code-server only when it remains localhost-bound
  and is exposed exclusively through private Tailscale Serve; otherwise use
  code-server authentication.
- Preserve `~/.local/share/code-server` and `~/.config/code-server` when migrating or rebuilding.

### Excalidraw

- Keep Excalidraw in Docker because it is an isolated web application and does not need host development tooling.
- Bind `127.0.0.1:8081:80` rather than publishing to all interfaces.
- A minimal container can use `--restart unless-stopped` and no volume unless a separate persistence/collaboration backend is intentionally configured.

### Cloudflare Tunnel

- Prefer `127.0.0.1` over `localhost` for explicit IPv4 loopback targets.
- Do not print the cloudflared service command line if it may contain a tunnel token.
- Cloudflare Access and the application's own authentication are separate layers.

#### Minimal Cloudflare setup

Configure the remotely managed tunnel in the Cloudflare dashboard under
**Zero Trust → Networks → Tunnels**.

Create these four public hostnames, replacing `<domain>` with the user's domain:

```text
opencode.<domain>  → http://127.0.0.1:4096  # standalone OpenCode mode
code.<domain>      → http://127.0.0.1:8080
draw.<domain>      → http://127.0.0.1:8081
```

In **Zero Trust → Access → Applications**, create a self-hosted application
covering those hostnames. Add a default-deny policy with an **Allow** rule for the
user's email identity. Enable independent MFA with TOTP and use a 7-day application
session with MFA reauthentication every 24 hours.

Keep the tunnel origins on loopback, require HTTPS at the public hostnames, and
ensure WebSockets are allowed for OpenCode and code-server. Cloudflare Access
protects the tunnel. Treat Access enrollment
links, session credentials, and tunnel tokens as
secrets.

References: [Cloudflare private applications](https://developers.cloudflare.com/cloudflare-one/setup/secure-private-apps/),
[Tunnel setup](https://developers.cloudflare.com/tunnel/get-started/).

## Maintenance

1. Run `scripts/verify.sh` before updating and record the current service/listener
   state.
2. Update components using their documented installer or package source; preserve
   service configuration and authentication data.
3. Restart only the service affected by the update, then verify its version, health,
   and expected localhost listener.
4. Run `scripts/verify.sh` again and investigate any new warnings before updating
   another component.

Updates can interrupt active agent sessions, terminals, browser connections, or
   WebSockets. Do not print service command lines or logs that may contain tokens.
Use the [OpenCode installation documentation](https://opencode.ai/en/docs) for
component-specific procedures.

## Workflow

1. Run `scripts/verify.sh` and summarize the current state before changing anything.
2. Compare actual listeners, services, Docker workloads, firewall rules, and tunnel state with the preferred architecture.
3. Resolve ownership conflicts first; never allow multiple OpenCode servers on the same port.
4. Make the smallest change that reaches the desired state.
5. After each service change, verify both systemd/container health and the expected localhost listener.
6. After networking changes, verify the service is still not unintentionally public.
7. After migrations, verify data/settings/extensions before deleting the old source.
8. Finish by rerunning `scripts/verify.sh` and report remaining warnings.

## Security review

Report these separately from functional setup; do not silently change them:

- public SSH exposure versus Tailscale-only SSH
- `PermitRootLogin`
- `PasswordAuthentication`
- SSH `X11Forwarding`
- Fail2ban status
- unattended security upgrades
- unexpected listeners on `0.0.0.0` or `[::]`
- Tailscale Funnel unexpectedly enabled

Use password-based OpenSSH over Tailscale as the approved access model; do not
recommend public SSH keys or Tailscale SSH unless the user changes this policy.

## Completion criteria

A setup is healthy when:

- code-server, OpenCode, Tailscale, and cloudflared services have the intended enabled/active state.
- In standalone OpenCode mode, exactly one backend listens on `127.0.0.1:4096`.
- code-server listens on `127.0.0.1:8080`.
- Excalidraw is the expected Docker workload and publishes only `127.0.0.1:8081:80`.
- Docker has no unexplained containers, volumes, networks, or build cache.
- no secrets appear in logs, skill files, or command output copied into the repository.
