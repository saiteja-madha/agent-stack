---
name: setup-vps
description: Audit, set up, and maintain a personal Ubuntu VPS for AI-assisted development using OpenCode, Codex CLI, code-server, Tailscale, Cloudflare Tunnel/Access, Docker, and Excalidraw. Use when provisioning or rebuilding the VPS, changing these services, checking exposure/firewall state, migrating workloads, or troubleshooting the AI development stack.
---

# Setup VPS

Maintain a small, secure AI-development VPS. Prefer simple host-native developer tooling, localhost-only listeners, and explicit private/reverse-proxy access.
This cookbook targets a single-user Ubuntu/Debian VPS with bash, systemd, sudo,
Docker, Tailscale, and Cloudflare Tunnel.

## Required intake

Before provisioning or rendering infrastructure files, discover or ask for these
values. Do not commit rendered values to the skill repository.

| Variable | Meaning | Example placeholder |
|---|---|---|
| `ADMIN_USER` | Non-root interactive administrator | `<admin-user>` |
| `TAILSCALE_HOSTNAME` | MagicDNS hostname for the VPS | `<tailscale-hostname>` |
| `PUBLIC_APP_DOMAIN` | Domain used for named public tools | `<public-app-domain>` |
| `PROJECT_DOMAIN` | Base domain for dynamically published projects | `<project-domain>` |
| `INFRA_ROOT` | Runtime infrastructure directory | `/home/<admin-user>/infra` |

Also ask whether any subnet routes, exit-node behavior, or host-specific network
ranges are required. Never embed owned domains, email identities, real hostnames,
public IP addresses, tunnel IDs, tokens, or passwords in this skill or its templates.

## Starting access policy

For a first-time setup, use `ADMIN_USER` as the only interactive SSH administrator. Keep
SSH password authentication enabled because this installation intentionally uses a
password over the private Tailscale network. Disable root SSH login with
`PermitRootLogin no`; do not delete or lock the root account until recovery access
has been verified. Permit SSH only through `tailscale0`, remove public IPv4 and IPv6
SSH firewall rules, and keep `ADMIN_USER` in the `sudo` group.

Before changing SSH or firewall access, keep the current session open and verify a
fresh `ADMIN_USER` login over Tailscale. After the change, validate both `sshd -T` and
the firewall rules. Never disable password authentication unless the user explicitly
changes this policy.

## Tailscale policy

Set the VPS Tailscale name to `TAILSCALE_HOSTNAME`. Tailscale is the only inbound network
for administration and development access. Use regular OpenSSH over the Tailscale
network with `ADMIN_USER` and password authentication; do not use Tailscale SSH.
Keep root SSH disabled. Allow future devices on the tailnet to connect.

Keep MagicDNS and automatic Tailscale updates enabled. Keep Funnel disabled. Do not
use this VPS as an exit node, subnet router, or route acceptor. Before removing any
advertised route, inspect the VPS and its current routes to confirm it is no longer
needed; apply its removal only after explicit approval.

OpenCode and code-server may run without application-level password authentication
only while they remain bound to localhost, every public route is protected by
Cloudflare Access, and private access is limited to the approved tailnet. Remove
stale routes when their target service is retired. Verify Tailscale state
automatically, but apply configuration changes only after explicit approval.

For direct tailnet access, prefer named Tailscale Services over machine-name paths
or alternate ports. Define an admin-owned service-host tag in the tailnet policy,
assign it to the VPS, and stop if the node remains untagged. For a single-user
tailnet where every present and future member device is trusted, an unrestricted
grant is acceptable:

```json
{
  "tagOwners": {
    "tag:vps-services": ["autogroup:admin"]
  },
  "grants": [
    {"src": ["*"], "dst": ["*"], "ip": ["*"]}
  ]
}
```

Do not add a Tailscale SSH policy when regular OpenSSH is used. Do not grant the
`funnel` node attribute. Define and advertise:

```text
svc:draw      tcp:443 → http://127.0.0.1:8081
svc:code      tcp:443 → http://127.0.0.1:8080
svc:opencode  tcp:443 → http://127.0.0.1:4096
```

Manually approve the tagged VPS as a host for each named service in the admin
console. Manual approval is the default for this small, stable service set; add
`autoApprovers.services` only if the user explicitly prefers automatic approval.
The private service URLs use Tailscale identity and grants and must not traverse
Cloudflare Access. Their domain suffix is the tailnet DNS name assigned by Tailscale;
do not embed it in the cookbook. Keep Funnel disabled. The public hostnames remain
separate Cloudflare Tunnel routes protected by Cloudflare Access. Keep the direct
OpenCode and code-server listeners on localhost; both may rely on Tailscale identity
on their private paths and Cloudflare Access on their public paths. Excalidraw may
likewise rely on Tailscale identity for private access.

After applying service configuration, verify that the node advertises all three
services, the admin console shows the host as approved, each MagicDNS URL works
from a tailnet device, and none works with Tailscale disconnected.

## SSH and firewall policy

Keep SSH on port `22` with password authentication enabled. Enforce
`AllowUsers ADMIN_USER` and `PermitRootLogin no`; retain the root account for local or
provider-console recovery. Allow SSH through `tailscale0` only. Keep application
ports bound to localhost by default, with exceptions requiring explicit approval.

Automate checks for public listeners and firewall exposure. Do not require fail2ban
for this Tailscale-only SSH design. Before any SSH or firewall change, keep the
current session open, obtain explicit approval, and require a successful fresh
`ADMIN_USER` session over Tailscale before considering the change complete.

## Docker policy

Enable the Docker daemon at boot and configure containers to restart automatically.
Use Docker Compose as the standard deployment method. Bind all container ports to
localhost by default. Use exact image tags or digests, never floating application
tags. Do not automate volume backups yet. Require explicit approval for destructive
Docker actions, including removing containers, images, volumes, networks, or build
cache.

## Reverse proxy and app publishing

Use Traefik as the local router for future projects. Keep the Cloudflare named
tunnel's `*.PROJECT_DOMAIN` origin pointed at `http://127.0.0.1:80`. Traefik must bind
only to `127.0.0.1:80`, use an immutable image digest, keep its dashboard disabled,
and use a dedicated Docker network named `proxy`.

Disable Docker exposure by default with `exposedByDefault=false`. Docker projects
are published only when their Compose service explicitly opts in with labels. Keep
published containers on the `proxy` network, use `expose` rather than host `ports`,
and specify the internal service port explicitly:

```yaml
labels:
  - traefik.enable=true
  - traefik.docker.network=proxy
  - traefik.http.routers.<name>.rule=Host(`<name>.<project-domain>`)
  - traefik.http.routers.<name>.entrypoints=web
  - traefik.http.services.<name>.loadbalancer.server.port=<internal-port>
```

Reuse the canonical files in `templates/traefik/` when rendering infrastructure.
Host-native applications use one YAML route file in
`INFRA_ROOT/traefik/dynamic/`. Because container-local `127.0.0.1` is not the VPS
loopback, the origin must be an explicitly approved private address reachable from
the Traefik container. A publish operation must validate the hostname and target
listener, write the route, validate Traefik, reload through its file watcher, and
verify the response. It must not publish a service by opening a public firewall
port.

Unknown hostnames must return a controlled 404. Do not expose the Traefik dashboard
or Docker socket through a route. Cloudflare Access remains responsible for
identity protection on public Cloudflare hostnames; local services remain bound to
localhost or private Docker networks.

## Toolchain and update policy

Install pnpm 12 with its official standalone installer, pinning the exact selected
12.x release during provisioning. Use pnpm runtime management to install and select
Node.js 24.x LTS globally; do not add NVM or Corepack. Keep npm optional and do not
manage it separately unless a project requires it. Use uv at its latest stable
release to manage Python versions, environments, and dependencies. Keep the Ubuntu
system Python available for OS tooling; select and pin Python per project, using the
newest stable version supported by that project.

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
| Node.js | 24.x LTS | pnpm 12 runtime management | Host | Resolve and pin an exact 24.x LTS release during provisioning |
| npm | Optional | Bundled with Node.js | Host | Do not manage separately unless a project requires it |
| pnpm | 12.x | Official standalone installer | Host | Pin an exact 12.x release; manage Node and project dependencies |
| uv | Latest stable | Official installer | Host | Use uv for Python installation, environments, and dependencies |
| Python | Managed by uv | uv | Host | Install alongside system Python |
| Docker Engine | Stable, current major | Official Docker APT repository | Host service | Controlled APT upgrades |
| Docker Compose | Latest stable | Docker Compose APT plugin | Host | Update with Docker |
| Docker CLI | Update with Docker | Official Docker APT repository | Host CLI | Update with Docker |
| OpenCode | Latest stable | Official standalone installer | `127.0.0.1:4096` | Manual stable updates |
| Codex CLI | Latest stable | Official `@openai/codex` npm package via pnpm | Host CLI | The package launches its bundled native executable; update manually |
| code-server | Latest stable | Official `.deb` installer | `127.0.0.1:8080` | Managed package updates |
| Tailscale | Latest stable | Official APT repository | Host service | Regular security updates |
| cloudflared | Latest stable | Official APT repository | Host service | Regular security updates |
| Traefik | v3.7 immutable digest | Docker image | `127.0.0.1:80` | Docker labels plus file provider; dashboard disabled |
| Excalidraw | Immutable digest | Docker Compose | `127.0.0.1:8081` | Render `templates/excalidraw/compose.yml` into `INFRA_ROOT/excalidraw` |

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
├── Traefik              127.0.0.1:80
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
- OpenCode may run without its own password only when it is bound to
  `127.0.0.1:4096`, every public route is protected by Cloudflare Access, and its
  private route is tailnet-only with Funnel disabled. Otherwise configure
  application authentication before starting it.
- The local `~/.opencode/package.json` and `node_modules` are supporting plugin
  dependencies, not the CLI installation.
- See the [official OpenCode installation documentation](https://opencode.ai/en/docs)
  and [server documentation](https://opencode.ai/v2/docs/cli/web).

### Codex

- Install Codex CLI from the official `@openai/codex` npm package with pnpm under
  the pnpm-managed Node 24 runtime. The package's launcher selects and runs its
  bundled native executable for the host platform; do not claim a separate official
  Linux native installer exists unless current OpenAI documentation adds one.
- An installation-source migration may be staged during an active Codex session
  when it does not overwrite or remove the executable that launched that session.
  Install to the new prefix, verify the new executable and authentication from a
  separate shell, then make the new prefix authoritative. Retain the old launcher
  as rollback until a fresh Codex session succeeds; remove NVM and Corepack only
  after that verification.
- Authenticate Codex separately from OpenCode.
- Do not add OpenAI OAuth to OpenCode merely because Codex is installed; keep provider authentication independent when that is the user's preference.

### code-server

- Prefer native code-server for this AI-development VPS so the editor, agents, Git, Node, Python, SSH configuration, and repositories share the host environment.
- Run it as `code-server@<user>` and bind only to `127.0.0.1:8080`.
- `auth: none` is acceptable for code-server only when it remains localhost-bound,
  every public route is protected by Cloudflare Access, and private access is
  limited to the approved tailnet; otherwise use code-server authentication.
- Preserve `~/.local/share/code-server` and `~/.config/code-server` when migrating or rebuilding.

### Excalidraw

- Keep Excalidraw in Docker because it is an isolated web application and does not need host development tooling.
- Deploy it with Docker Compose under `INFRA_ROOT/excalidraw`, rendering
  `templates/excalidraw/compose.yml` with an explicitly selected immutable digest.
- Bind `127.0.0.1:8081:80`, use `restart: unless-stopped`, and do not add a volume
  unless a separate persistence or collaboration backend is intentionally configured.

### Cloudflare Tunnel

- Prefer `127.0.0.1` over `localhost` for explicit IPv4 loopback targets.
- Do not print the cloudflared service command line if it may contain a tunnel token.
- Cloudflare Access and the application's own authentication are separate layers.

#### Minimal Cloudflare setup

Configure the remotely managed tunnel in the Cloudflare dashboard under
**Zero Trust → Networks → Tunnels**.

Create these named public hostnames using `PUBLIC_APP_DOMAIN`:

```text
opencode.<public-app-domain>  → http://127.0.0.1:4096
code.<public-app-domain>      → http://127.0.0.1:8080
draw.<public-app-domain>      → http://127.0.0.1:8081
*.<project-domain>            → http://127.0.0.1:80
<project-domain>              → http://127.0.0.1:80
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

Apply Ubuntu security updates through the configured security origins. When a new
kernel or core libraries require a reboot, verify SSH and Tailscale first, then use
a controlled reboot and confirm the expected kernel and all stack services return.

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
- the approved tagged node advertises `svc:draw`, `svc:code`, and `svc:opencode`
  when named private services are enabled.
- In standalone OpenCode mode, exactly one backend listens on `127.0.0.1:4096`.
- code-server listens on `127.0.0.1:8080`.
- Excalidraw is the expected Docker workload and publishes only `127.0.0.1:8081:80`.
- Docker has no unexplained containers, volumes, networks, or build cache.
- no secrets appear in logs, skill files, or command output copied into the repository.
