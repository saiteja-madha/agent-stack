---
name: vps-ops
description: Set up, audit, secure, maintain, migrate, and troubleshoot a personal Ubuntu VPS for AI-assisted development. Use for provisioning or rebuilds, health and exposure reviews, stack updates or migrations, and creating or reviewing Docker Compose or publishing configurations intended for this VPS. Covers Docker, Traefik, Tailscale, Cloudflare Tunnel/Access, and the host development tools.
---

# Setup VPS

Maintain a single-user Ubuntu AI-development VPS with host-native developer
tools, localhost-only applications, Docker, Tailscale, and Cloudflare Tunnel. If
the host runs Debian, identify its release and adapt package and service details
before making changes; the tool inventory targets Ubuntu 22.04.

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

Use `ADMIN_USER` as the only interactive SSH administrator and keep it in `sudo`.
Keep SSH on port 22 with password authentication, enforce `AllowUsers ADMIN_USER`
and `PermitRootLogin no`, and retain root for provider-console recovery. Permit SSH
only through `tailscale0`; remove public IPv4 and IPv6 SSH firewall rules. Do not
require fail2ban for this private-only design.

Before changing SSH or firewall access, keep the current session open and verify a
fresh `ADMIN_USER` login over Tailscale. Validate `sshd -T`, firewall rules, and
public exposure afterward; do not consider the change complete until a fresh
Tailscale SSH session succeeds. Never change this authentication model without
explicit approval.

## Tailscale policy

Set the VPS name to `TAILSCALE_HOSTNAME`. Tailscale is the only inbound network for
administration and development. Use regular OpenSSH, not Tailscale SSH, and allow
future tailnet devices.

Keep MagicDNS and automatic Tailscale updates enabled. Keep Funnel disabled. Do not
use this VPS as an exit node, subnet router, or route acceptor. Before removing any
advertised route, inspect the VPS and its current routes to confirm it is no longer
needed; apply its removal only after explicit approval.

OpenCode and code-server may omit application passwords only while bound to
localhost. Cloudflare Access protects every public route, and private access is
tailnet-only. Remove stale routes with retired services. Audit automatically, but
apply Tailscale changes only with explicit approval.

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
svc:t3code    tcp:443 → http://127.0.0.1:3773
```

Manually approve the tagged VPS for each service; use `autoApprovers.services` only
if requested. Private URLs use Tailscale identity and grants, not Cloudflare Access;
public hostnames use Cloudflare Tunnel and Access. Never embed the tailnet DNS suffix.

After applying service configuration, verify that the node advertises all four
services, the admin console shows the host as approved, each MagicDNS URL works
from a tailnet device, and none works with Tailscale disconnected.

## Docker policy

Enable the Docker daemon at boot and configure containers to restart automatically.
Use Docker Compose as the standard deployment method. For directly accessed host
ports, bind to `127.0.0.1` by default. For container-only communication, use a Docker
network without publishing a host port. For Traefik-published apps, use `expose` and
explicit routing labels as described below. Pin application images to exact tags or
digests; never use floating tags. Do not automate volume backups yet. Require
explicit approval before removing containers, images, volumes, networks, or build
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
identity protection on public Cloudflare hostnames.

## Toolchain and update policy

Install pnpm 12 with its official standalone installer, pinning the exact selected
12.x release during provisioning. Use pnpm runtime management to install and select
Node.js 24.x LTS globally; do not add NVM or Corepack. Use uv at its latest stable
release to manage Python versions, environments, and dependencies. Keep the Ubuntu
system Python available for OS tooling; select and pin Python per project, using the
newest stable version supported by that project.

OpenCode, Codex CLI, code-server, Tailscale, and cloudflared track their latest
stable releases using their documented install sources. Docker Engine tracks the
stable current major through Docker's official APT repository; Docker Compose uses
the Docker Compose APT plugin and updates with Docker. Git tracks the latest Ubuntu
APT version. Ubuntu receives security updates only.

Maintenance is a separate operation. Independent updates may run in parallel, but
verify each afterward. Service restarts require approval. Preserve rollback where
supported; otherwise stop and report the limitation. Keep procedures conceptual
with minimal reproducible steps.

Before maintenance, run `scripts/check-updates.sh` to compare installed versions,
local APT candidates, upstream stable releases, managed Python interpreters, and
running container image references. It is read-only: it does not refresh APT package
indexes, install updates, or restart services. APT results reflect the local package
index and may be stale; report unavailable upstream checks rather than treating them
as current. Rerun it after maintenance to confirm the result.

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
| T3 Code | Latest stable | Official standalone installer | `127.0.0.1:3773` | Runs as `t3code.service` (user unit); connects to OpenCode on `127.0.0.1:4096` |

## Safety rules

- Never expose API keys, OAuth tokens, Cloudflare tunnel tokens, passwords, private SSH keys, or `.env` contents in output, logs, or repository files; never request these secrets in chat.
- Do not run destructive Docker/system cleanup, remove volumes, uninstall software, alter firewall rules, or change SSH authentication without explicit user approval.
- Before deleting a service or volume, identify what owns it and whether persistent data has been backed up or migrated.
- Prefer exact service/container names over broad `pkill`, `docker system prune --volumes`, or similar blanket cleanup.

### OpenCode

- Install the host-native OpenCode CLI with its official user-local installer:

  ```bash
  curl -fsSL https://opencode.ai/v2/install | bash
  ```

  Expect `~/.opencode/bin/opencode`; do not substitute apt, Homebrew, or global npm.
- Run exactly one OpenCode server on `127.0.0.1:4096` with
  `opencode serve --hostname 127.0.0.1 --port 4096` to follow the localhost-only
  authentication policy.
- The local `~/.opencode/package.json` and `node_modules` are supporting plugin
  dependencies, not the CLI installation.

### Codex

- Install official `@openai/codex` with pnpm under pnpm-managed Node 24. Its launcher
  runs the bundled platform binary; do not claim a separate official Linux native
  installer exists unless current OpenAI documentation adds one.
- An installation-source migration may be staged during an active Codex session
  when it does not overwrite or remove the executable that launched that session.
  Install to the new prefix, verify the new executable and authentication from a
  separate shell, then make the new prefix authoritative. Retain the old launcher
  as rollback until a fresh Codex session succeeds; remove NVM and Corepack only
  after that verification.
- Authenticate Codex separately; do not add OpenAI OAuth to OpenCode implicitly.

### code-server

- Use native code-server so editor and development tools share the host environment.
- Run it as `code-server@<user>` and bind only to `127.0.0.1:8080` to follow the
  localhost-only authentication policy.
- Preserve `~/.local/share/code-server` and `~/.config/code-server` when migrating or rebuilding.

### Excalidraw

- Keep Excalidraw in Docker.
- Deploy it with Docker Compose under `INFRA_ROOT/excalidraw`, rendering
  `templates/excalidraw/compose.yml` with an explicitly selected immutable digest.
- Bind `127.0.0.1:8081:80`, use `restart: unless-stopped`, and do not add a volume
  unless a separate persistence or collaboration backend is intentionally configured.

### T3 Code
- Install with the official standalone installer; run as `t3code.service` (user unit)
  on `127.0.0.1:3773`. Do not launch a separate `t3 serve` manually.
- Point T3 Code at the external OpenCode server `http://127.0.0.1:4096` so it does
  not spawn its own OpenCode instance.
- Expose privately via `svc:t3code` (`127.0.0.1:3773`); disable T3 Connect.
- With T3 Connect disabled and exposure via `svc:t3code`, T3 Code does not
  spawn its own cloudflared or OpenCode instances. If T3 Connect or quick tunnels
  are enabled, T3 may spawn a cloudflared Quick Tunnel; report it for manual
  review rather than auto-excluding. OpenCode `--service` instances are not
  T3-managed and require investigation.
### Cloudflare Tunnel

- Prefer `127.0.0.1` over `localhost` for explicit IPv4 loopback targets.
- Do not print the cloudflared service command line if it may contain a tunnel token.
- Cloudflare Access and the application's own authentication are separate layers.

#### Minimal Cloudflare setup

In **Zero Trust → Networks → Tunnels**, configure these public hostnames:

```text
opencode.<public-app-domain>  → http://127.0.0.1:4096
code.<public-app-domain>      → http://127.0.0.1:8080
draw.<public-app-domain>      → http://127.0.0.1:8081
*.<project-domain>            → http://127.0.0.1:80
<project-domain>              → http://127.0.0.1:80
```

Create one self-hosted Access application covering them, default-deny except the
user's email identity. Enable TOTP MFA, a 7-day application session, and MFA
reauthentication every 24 hours. Require public HTTPS, allow WebSockets for OpenCode
and code-server, and treat enrollment links, sessions, and tunnel tokens as secrets.

References: [Cloudflare private applications](https://developers.cloudflare.com/cloudflare-one/setup/secure-private-apps/),
[Tunnel setup](https://developers.cloudflare.com/tunnel/get-started/).

## Workflow

1. Start with `scripts/verify.sh` and compare the current state with this policy.
   For maintenance, also run `scripts/check-updates.sh` before and after updates.
2. Resolve ownership conflicts, then make the smallest change that reaches the
   requested state. Preserve configuration and authentication data; verify the
   affected versions, health, listeners, and exposure afterward.
3. For migrations, verify data, settings, extensions, and a fresh session before
   removing the old source.
4. Report remaining warnings. Maintenance uses documented install sources and
   Ubuntu security origins; preserve rollback where supported. Restarts require
   approval. For kernel or core-library updates, verify SSH and Tailscale around a
   controlled reboot. Updates may interrupt sessions and WebSockets.

## Security review

Report, but never silently change: SSH exposure, `PermitRootLogin`,
`PasswordAuthentication`, `X11Forwarding`, fail2ban, unattended security updates,
wildcard listeners, and unexpected Tailscale Funnel. A wildcard listener shows
which interfaces accept connections; it does not by itself prove public internet
reachability. Report host firewall and provider-firewall evidence separately, and
only claim external reachability when confirmed from outside the VPS or by
authoritative provider firewall configuration.

## Completion criteria

A setup is healthy when services are enabled and active as intended; listeners match
the inventory; the approved tagged node advertises `svc:draw`, `svc:code`,
`svc:opencode`, and `svc:t3code`; and Docker has no unexplained resources.
