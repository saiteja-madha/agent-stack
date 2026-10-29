---
name: vps-ops
description: Set up, audit, secure, maintain, migrate, and troubleshoot a personal Ubuntu VPS for AI-assisted development. Use for provisioning or rebuilds, health and exposure reviews, stack updates or migrations, and creating or reviewing Docker Compose or publishing configurations intended for this VPS. Covers Docker, Traefik, Tailscale, Cloudflare Tunnel/Access, and the host development tools.
---

# Setup VPS

Maintain a single-user Ubuntu AI-development VPS with host-native developer
tools, localhost-only applications, Docker, Tailscale, and Cloudflare Tunnel. If
the host runs Debian, identify its release and adapt package and service details
before making changes. Fresh installs target Ubuntu Server 26.04 LTS, using its
latest stable point release; adapt audit commands to the installed OS.

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
and `PermitRootLogin no`, and retain root for provider-console recovery. Bind
OpenSSH to the VPS Tailscale addresses and allow inbound SSH only on `tailscale0`;
remove public IPv4 and IPv6 SSH firewall rules. Do not require fail2ban for this
private-only design.

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

Tailscale-only applications may omit optional application authentication while
bound to loopback and published only through Tailscale. OpenCode v2 requires a
password; Hermes uses dashboard password authentication for its Desktop app.
Hindsight UI needs no application password in this private setup. Cloudflare
Access protects every public route. Remove stale routes with retired services;
audit automatically, but apply Tailscale changes only with explicit approval.

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
svc:hermes    tcp:443 → http://127.0.0.1:9119
svc:hindsight tcp:443 → http://127.0.0.1:9999
```

Manually approve the tagged VPS for each service; use `autoApprovers.services` only
if requested. Private URLs use Tailscale identity and grants, not Cloudflare Access;
public hostnames use Cloudflare Tunnel and Access. Never embed the tailnet DNS suffix.

After applying service configuration, verify that the node advertises all six
services above, the admin console shows the host as approved, each MagicDNS URL works
from a tailnet device, and none works with Tailscale disconnected.

## Docker policy

Enable the Docker daemon at boot and configure containers to restart automatically.
Use Docker Compose as the standard deployment method. For directly accessed host
ports, bind to `127.0.0.1` by default. For container-only communication, use a Docker
network without publishing a host port. For Traefik-published apps, use `expose` and
explicit routing labels as described below. Pin application images to exact tags or
digests; never use floating tags. Do not automate volume backups yet. Require
explicit approval before removing containers, images, volumes, networks, or build
cache. Docker-published ports can bypass UFW filtering; inspect actual bindings
and Docker firewall rules rather than treating UFW alone as proof of isolation.

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
APT version. Ubuntu receives security updates only. Verify effective
`APT::Periodic::Unattended-Upgrade` is enabled and permitted origins are restricted
to the intended Ubuntu security origins; service enablement alone is insufficient.

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

Keep this table as the desired policy; record resolved versions, image digests and
verification dates in a private inventory under `INFRA_ROOT`, not in this skill.
Pin application versions and container images before installation. System utilities
may explicitly track the latest version from the configured Ubuntu OS repository when noted in the
table; do not use floating application or container tags such as `latest`.

| Tool | Desired version | Install source | Service/listener | Notes |
|---|---|---|---|---|
| Ubuntu Server | 26.04 LTS, latest stable point release | Provider | apply security updates | Verify package sources support this release |
| Git | latest | `apt` | Host | Intentionally tracks the latest configured OS repository version |
| Bitwarden CLI (`bws`) | Selected stable release | Official Bitwarden Secrets Manager distribution | Host CLI | Machine-account authentication |
| bwenv | Selected release pinned by version and checksum | Official project release installer | Host CLI | App namespaces in the `local` Bitwarden project |
| GitHub CLI (`gh`) | Latest stable; resolve exact version during provisioning | Official GitHub CLI APT repository | Host CLI; no listener | Authenticate as the administrator; preserve configuration securely |
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
| Hermes Agent | Selected stable release | Official installer | Dashboard `127.0.0.1:9119`; user service | Standalone host install; dashboard and Desktop app, no messaging gateway |
| Hindsight | Immutable full-image digest | Docker Compose | API `127.0.0.1:8888`, UI `127.0.0.1:9999` | Full image runs API, UI, embeddings and reranking; UI via `svc:hindsight` |
| Hindsight PostgreSQL | Compatible pgvector image digest; pin major | Docker Compose | Container network only | Persistent named volume; separate from project databases |

## Safety rules

- Never expose API keys, OAuth tokens, Cloudflare tunnel tokens, passwords, private SSH keys, or `.env` contents in output, logs, or repository files; never request these secrets in chat.
- Do not run destructive Docker/system cleanup, remove volumes, uninstall software, alter firewall rules, or change SSH authentication without explicit user approval.
- Before deleting a service or volume, identify what owns it and whether persistent data has been backed up or migrated.
- Prefer exact service/container names over broad `pkill`, `docker system prune --volumes`, or similar blanket cleanup.

## Secrets with bwenv

Use Bitwarden Secrets Manager's existing **`local` project** (environment), with
`opencode`, `hermes`, `hindsight` and optional `cloudflared` bwenv app namespaces.
`BWS_PROJECT_ID` selects the project's UUID, not its display name.

Install pinned stable versions of the official `bws` CLI and
[bwenv](https://github.com/saiteja-madha/bwenv); verify release checksums and version
output. Install executables into an explicitly configured service PATH. Assign a
separate **`vps-runtime` machine account** read-only access to `local`, and issue a
host-specific token. Manage secret creation/rotation through the user's Bitwarden
UI or separately authorized write-capable credentials, never the runtime token.
Multiple machine accounts may share `local`. App prefixes filter injection, not
Bitwarden authorization: a token with project access can read all that project's
secrets. Do not enable shared-value injection unless needed.

Required stored secret names:

| Bitwarden key | Injected variable / use |
|---|---|
| `opencode__OPENCODE_PASSWORD` | Stable OpenCode v2 server password; also configure T3's client |
| `hermes__HERMES_DASHBOARD_BASIC_AUTH_USERNAME` | Dashboard/app login username |
| `hermes__HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` | Dashboard/app login password |
| `hermes__HERMES_DASHBOARD_BASIC_AUTH_SECRET` | Stable session-signing key; generate at least 32 random bytes, hex encoded |
| `hindsight__HINDSIGHT_DB_PASSWORD` | Generate a random hex PostgreSQL password; not a dashboard login |
| `cloudflared__TUNNEL_TOKEN` | Only for a remotely managed token-based tunnel |

Keep usernames, domains, HTTPS service URLs, ports, model selections and immutable
image pins in ordinary runtime configuration or appropriate private version
control. The Hermes login username is stored alongside its password for convenient
injection; it is not itself sensitive. Do not put Codex's rotating OAuth files in
bwenv; use the dedicated Hindsight login directory below.

### Bootstrap and service wiring

- Create `~/.config/vps-ops/` mode 0700. Store the machine token in `bws-token`
  mode 0600 through secure secret input, never shell history or command arguments.
  Render `templates/secrets/runtime.env` into `runtime.env` with the project UUID,
  complete absolute service PATH and exact Hermes Tailscale HTTPS origin. Use
  systemd EnvironmentFile syntax, not shell substitutions. Configure the same
  Bitwarden region/profile for service and interactive access.
- Install `scripts/vps-bwenv-exec.py` as an executable in `~/.local/bin`. Templates
  supply the token through systemd `LoadCredential`. The wrapper invokes bwenv,
  validates required values and blocks token inheritance by applications. For an
  interactive operation, securely supply `BWS_ACCESS_TOKEN` and the non-secret
  configuration; `APP --check-only` validates without starting a service.
- Render OpenCode's system-unit template with the actual administrator/home paths;
  install Hermes and Hindsight templates as user units, adjusting `INFRA_ROOT`.
  Enable linger and administrator Docker access (root-equivalent control). Use
  configured service PATHs rather than login-shell initialization. Inspect the
  existing cloudflared unit before applying its optional token-managed drop-in.
- Secret fetches require Bitwarden at service start/restart and Compose updates.
  Templates retry boot/readiness failures; never substitute blank/default secrets.
  User units cannot order reliably after system Docker/network units. Docker
  restarts existing containers from saved configuration without refetching secrets;
  `hindsight.service` reapplies Compose at user-manager startup, and stopping the
  unit stops its stack.
- After rotation, update every consumer and restart/recreate only with approval.
  PostgreSQL also requires changing the existing database role password: environment
  changes alone do not rotate it. Do not rotate secrets merely to test access.
- Never print fetched environments, secret-rendered Compose, or bwenv secret output
  during audits. Injection still leaves values in process environments, Docker
  metadata and required client storage; it does not hide them from root/Docker
  administrators. The underlying bws CLI may retain encrypted authentication state.
  Keep the bootstrap token independently accessible for a fresh install.

References: [bwenv CLI](https://github.com/saiteja-madha/bwenv/blob/main/docs/reference/cli.md),
[Bitwarden machine accounts](https://bitwarden.com/help/machine-accounts/),
[Bitwarden CLI](https://bitwarden.com/help/secrets-manager-cli/).

## Application setup

### GitHub CLI

- Install `gh` from the [official GitHub CLI APT repository](https://github.com/cli/cli/blob/trunk/docs/install_linux.md),
  recording the selected stable version. Keep it separate from the Ubuntu Git package.
- Authenticate as `ADMIN_USER`, not root, using the documented
  [`gh auth login`](https://cli.github.com/manual/gh_auth_login) browser/device flow.
  For HTTPS Git operations, configure `gh auth setup-git` when desired; preserve
  an existing SSH-based Git setup unless a change is requested.
- Treat `~/.config/gh` and any credential-store entries as secrets. Preserve them
  securely for recovery or authenticate again after rebuilding. Headless systems
  may fall back to plaintext credential storage; never print `hosts.yml`, tokens,
  or `gh auth token` output.
- Verify `gh --version`, authentication with `gh auth status` (never `--show-token`),
  and read-only access to an intended repository. Check the installed APT source
  and candidate during maintenance; an installed distro package does not establish
  that the official GitHub CLI repository is configured.

### OpenCode

- Install the host-native OpenCode CLI with its official user-local installer:

  ```bash
  curl -fsSL https://opencode.ai/v2/install | bash
  ```

  Expect `~/.opencode/bin/opencode`; do not substitute apt, Homebrew, or global npm.
- Run exactly one OpenCode server on `127.0.0.1:4096` with
  `opencode serve --hostname 127.0.0.1 --port 4096` to follow the localhost-only
  binding policy. Run it through the supplied system unit and bwenv's `opencode`
  namespace. Set `OPENCODE_PASSWORD`; never rely on an ephemeral generated password.
  OpenCode v2's HTTP Basic username is always `opencode`. Verify unauthenticated
  `/api/info` fails and the configured credentials succeed. Use the pinned v2
  release's documented pairing flow for browser/app access, without enabling its
  public remote tunnel. Treat startup/pairing output as potentially secret-bearing.
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
  `templates/excalidraw/compose.yml` with `EXCALIDRAW_IMAGE` set to an explicitly
  selected immutable digest (for example in a private runtime `.env`).
- Bind `127.0.0.1:8081:80`, use `restart: unless-stopped`, and do not add a volume
  unless a separate persistence or collaboration backend is intentionally configured.

### T3 Code
- Install with the official standalone installer; run as `t3code.service` (user unit)
  on `127.0.0.1:3773`. Do not launch a separate `t3 serve` manually.
- Point T3 Code at the external OpenCode server `http://127.0.0.1:4096` so it does
  not spawn its own OpenCode instance. Configure the external connection's password
  from `opencode__OPENCODE_PASSWORD` through T3's supported settings/credential API.
  The audited release uses `providerInstances.opencode.config.serverUrl` and
  `serverPassword`; recheck the installed release before writing settings. Do not
  assume merely setting `OPENCODE_PASSWORD` on T3 configures its client. Avoid
  printing settings containing credentials and retain owner-only permissions.
  Verify a real OpenCode-backed session in T3; update its stored password whenever
  the server password rotates.
- Expose privately via `svc:t3code` (`127.0.0.1:3773`); disable T3 Connect.
- With T3 Connect disabled and exposure via `svc:t3code`, T3 Code does not
  spawn its own cloudflared or OpenCode instances. If T3 Connect or quick tunnels
  are enabled, T3 may spawn a cloudflared Quick Tunnel; report it for manual
  review rather than auto-excluding. OpenCode `--service` instances are not
  T3-managed and require investigation.

### Hermes and Hindsight

#### Deployment

Keep Hermes standalone on the host, running
`templates/hermes/hermes-dashboard.service` as a user unit. Use the dashboard and
Hermes Desktop app; omit the messaging gateway and bot integrations.

The service fetches the `hermes` namespace. Its exact Tailscale HTTPS origin in
`HERMES_DASHBOARD_PUBLIC_URL` permits proxy Host/WebSocket Origin values and engages
the auth gate on the loopback listener. Enable the bundled basic provider with the
stored username, password and stable signing secret. In Desktop, use Settings →
Gateways → Remote gateway with that URL and dashboard credentials. Model-provider
login is separate from dashboard authentication.

Run the full Hindsight image and dedicated PostgreSQL/pgvector in Docker using
`templates/hindsight/compose.yml`. It includes the API, UI, local embeddings and
reranking; PostgreSQL persists memory in a named volume. Hermes needs only the
integration plugin/client dependencies, not a host Hindsight API or embedded daemon.
Use the inventory's loopback ports and Tailscale service mappings; publish only the
Hindsight UI, without an app password. Its API connection stays inside the container.
Neither Hermes nor Hindsight needs a Cloudflare route.

#### Fresh installation

1. Select the stable Hermes release, reviewed Hindsight plugin commit, full image
   digest, compatible pgvector digest and PostgreSQL major. Use the official Hermes
   installer's release-selection options. Keep Hermes-managed runtime dependencies
   separate from the host toolchain; do not hard-code old installation paths.
2. Render the Compose template into `INFRA_ROOT/hindsight`. Put non-secret image
   references and `HINDSIGHT_API_LLM_MODEL` in `.env`; fetch the generated hex
   database password through bwenv. Keep it stable when reusing the volume.
   Verify embedding/reranking defaults and disk/RAM needs for the pinned full image;
   slim images require external model services and are not interchangeable.
3. Prepare subscription authentication below, then validate via
   `vps-bwenv-exec.py hindsight docker compose config --quiet`. Enable/start the
   rendered `hindsight.service` user unit when provisioning is authorized.
   Database readiness does not prove API/model readiness. Check the template's
   explicit PGDATA location against the selected PostgreSQL image.
4. Install `hermes plugins install hindsight`, then use `hermes memory setup` to
   select **Local External**. In `$HERMES_HOME/hindsight/config.json`, set JSON keys
   `mode` to `local_external` and `api_url` to `http://127.0.0.1:8888`. Activate
   `memory.provider: hindsight` in Hermes config and choose bank mappings/memory mode;
   plugin installation alone does not activate it.
5. Enable the dashboard user unit and configure Hermes's model login separately
   from Hindsight OAuth. Advertise the two named services under the Tailscale policy
   and perform the integration checks below.

#### Hindsight subscription authentication

Use `openai-codex`, not an API key or an implicit paid-provider fallback. Create a
fresh, separately authorized credential store: sharing an interactive Codex auth
file can cause refresh-token conflicts. The Compose template mounts `codex-auth`
read-write at `/var/lib/hindsight/codex`, selected by
`HINDSIGHT_API_LLM_CODEX_HOME`. Preserve it across container recreation.

During provisioning, build the temporary `templates/hindsight/Dockerfile.codex-login`
helper with an immutable Node 24 `NODE_IMAGE` and exact stable `CODEX_VERSION`.
Mount `INFRA_ROOT/hindsight/codex-auth` at `/home/node/.codex` and run interactively.
The entrypoint uses `codex login --device-auth` with file credential storage; the
host's `~/.codex` is never mounted or changed. Prepare ownership for the helper's
`node` user, then for Hindsight's pinned runtime UID/GID before starting that service.
Use directory mode 0700 and auth-file mode 0600 so refreshes can persist securely.

Show the CLI-generated URL/code so the user can consent on another device; keep the
process alive until it succeeds. Never invent or persist the one-time code. If it
expires, start a fresh flow when the user is ready. Device login may require account/
workspace enablement. Exit success and a nonempty private `auth.json` are prerequisites;
retain/reflect verifies actual provider access. If unsupported, report the limitation
rather than changing providers. Revocation can require reauthentication; after a
rebuild, use a fresh login. Do not build or start login flows merely to edit/audit
this skill.

#### Integration verification

- Dashboard and stack user units enabled/active; verify container/database health
  independently of the oneshot stack unit and check the pinned API health endpoint.
- `hermes memory status` reports external Hindsight available in the dashboard's
  selected profile. Retain a harmless memory, await ingestion, recall and reflect;
  HTTP health alone does not test LLM credentials or model operations.
- During approved restart testing, memory survives container recreation without
  volume removal. Verify real bank operations through the UI from another tailnet
  device, alongside the general authentication/boot checks below.
- Record the plugin commit, PostgreSQL major and bank mapping with resolved tool
  versions/image digests in the private runtime inventory.

References: [Hermes installation](https://hermes-agent.nousresearch.com/docs/getting-started/installation),
[Hermes dashboard/app authentication](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard),
[Hindsight plugin](https://hermes-agent.nousresearch.com/docs/plugins/hindsight),
[Hindsight Compose](https://github.com/vectorize-io/hindsight/blob/main/docker/docker-compose/external-pg/docker-compose.yaml),
[Hindsight configuration](https://hindsight.vectorize.io/developer/configuration),
[Hindsight provider authentication](https://hindsight.vectorize.io/developer/models),
[OpenAI authentication](https://learn.chatgpt.com/docs/auth).
Recheck release-specific options when provisioning.

### Cloudflare Tunnel

- Prefer `127.0.0.1` over `localhost` for explicit IPv4 loopback targets.
- Do not print the cloudflared service command line if it may contain a tunnel token.
- Cloudflare Access and the application's own authentication are separate layers.
- For a remotely managed token-based tunnel, use
  `templates/cloudflared/bwenv.conf` with the optional `cloudflared` namespace.
  `cloudflared tunnel --no-autoupdate run` reads `TUNNEL_TOKEN` from its environment;
  never embed it in ExecStart or a command argument. Locally managed credential-file
  tunnels retain their documented credential-file flow instead.

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

## Authentication and boot verification

After authorized provisioning, run the wrapper's `APP --check-only` for each
configured namespace, using the service's LoadCredential/EnvironmentFile context
or securely supplied interactive bootstrap. Confirm the project's UUID maps to
`local` and inspect account permissions in Bitwarden; environment injection alone
does not establish scope.

Run `scripts/verify-app-auth.py opencode` and `hermes` under their respective
wrapper contexts. These opt-in probes verify unauthenticated rejection and valid
login without printing credentials/responses; Hermes creates a temporary session.
They are separate from the baseline inventory, which never fetches secrets or
logs in. Inspect pinned API documentation if a probe fails; do not disable auth.

Test a real OpenCode-backed T3 session and Hermes Desktop chat/WebSockets through
Tailscale HTTPS. Hermes login must survive an approved service restart. During an
approved reboot test, verify services recover without interactive shell login,
secret fetch works, application environments exclude the machine token, and
listeners remain private. Inspect environments without displaying their values.

## Completion criteria

Services are enabled and active as intended, listeners match the inventory, all
named services pass the Tailscale policy's approval/access checks, and Docker has
no unexplained resources. Complete application integration and authentication/boot
checks above; the best-effort baseline script alone does not establish compliance.
