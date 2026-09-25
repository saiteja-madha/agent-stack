---
name: setup-vps
description: Audit, set up, and maintain a personal Ubuntu VPS for AI-assisted development using T3 Code, OpenCode, Codex CLI, code-server, Tailscale, Cloudflare Tunnel/Access, Docker, and Excalidraw. Use when provisioning or rebuilding the VPS, changing these services, checking exposure/firewall state, migrating workloads, or troubleshooting the AI development stack.
compatibility: Ubuntu/Debian VPS with bash, systemd, sudo, Docker, Tailscale, and Cloudflare Tunnel. Intended for a single-user AI development VPS.
---

# Setup VPS

Maintain a small, secure AI-development VPS. Prefer simple host-native developer tooling, localhost-only listeners, and explicit private/reverse-proxy access.

## Safety rules

- Start with a read-only audit. Run `scripts/verify.sh` before proposing changes.
- Never print, commit, or request API keys, OAuth tokens, T3 pairing tokens, Cloudflare tunnel tokens, passwords, private SSH keys, or `.env` contents.
- Do not run destructive Docker/system cleanup, remove volumes, uninstall software, alter firewall rules, or change SSH authentication without explicit user approval.
- Before deleting a service or volume, identify what owns it and whether persistent data has been backed up or migrated.
- Prefer exact service/container names over broad `pkill`, `docker system prune --volumes`, or similar blanket cleanup.
- Keep application ports on `127.0.0.1` unless there is a specific reason to expose them.
- Use Tailscale or Cloudflare Tunnel instead of opening application ports in the public firewall.

## Preferred architecture

Use this layout unless the user explicitly chooses otherwise:

```text
VPS host
├── T3 Code             127.0.0.1:3773
│   └── T3 Connect       → account-based remote access
├── OpenCode            127.0.0.1:4096 (standalone backend)
│   └── Cloudflare Access/Tunnel
├── Codex CLI           host-native, authenticated separately
├── code-server         127.0.0.1:8080
│   └── Cloudflare Access/Tunnel
├── cloudflared         host service
├── tailscaled          host service
└── Docker
    └── Excalidraw      127.0.0.1:8081 → Cloudflare Access/Tunnel
```

### T3 Code

- Run T3 as the user's systemd user service.
- Keep T3 listening on `127.0.0.1:3773`.
- Use T3 Connect for account-based laptop/mobile access.
- Ensure systemd user lingering is enabled so the T3 user service survives logout/reboot.

#### Official documentation

Keep the T3-specific procedure aligned with the upstream documentation:

- [Install and first run](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md)
- [Linux background service](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)
- [Remote access](https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md)
- [Keeping the app and server in sync](https://github.com/pingdotgg/t3code/blob/main/docs/user/updating.md)
- [Upstream repository](https://github.com/pingdotgg/t3code)

#### Reproducible Linux setup

Run these commands as the normal development user, never as `root`:

```bash
# Official installer; pin with T3CODE_VERSION when a fixed release is required.
curl -fsSL https://t3.codes/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

t3 --version
t3 service install
t3 service status
```

The installer places the launcher in `~/.local/bin`. Persist that directory in the
user's normal shell configuration if the installer tells you it is not already on
`PATH`. On Linux, `t3 service install` creates the user service and enables lingering;
if it reports that lingering needs administrator approval, run only:

```bash
sudo loginctl enable-linger "$(id -un)"
```

Then rerun `t3 service install`. Do not run T3 with `sudo`, because that creates a
separate root installation and identity.

The service should result in `t3code.service`, a listener on
`127.0.0.1:3773`, and a service that remains available after logout and reboot.
Verify without printing logs that may contain sensitive data:

```bash
t3 service status
systemctl --user is-active t3code.service
ss -ltnH 'sport = :3773'
loginctl show-user "$(id -un)" --property=Linger
```

#### T3 Connect

Do not expose port `3773` publicly.

On the VPS, run as the normal development user:

```bash
export PATH="$HOME/.local/bin:$PATH"
t3 connect link --headless
t3 service restart
t3 connect status
t3 service status
```

The headless link prints a browser URL and short authorization code. Approve it from
another device while signed in to the same T3 account. Then choose the `homelab`
environment in T3 Code on the client. `t3 connect login --headless` only authorizes
the CLI; it does not publish the environment. T3 Connect renews access credentials,
so it is preferable to repeatedly issuing pairing links for long-lived personal use.

Use these controls to manage the connection without exposing credentials:

```bash
t3 connect status
t3 connect unlink       # disable remote access but retain authorization
t3 connect logout       # disable remote access and clear authorization
```

T3 Connect is separate from Cloudflare Access. It provides the T3 environment
connection; Cloudflare remains an independent web route.

#### Providers and updates

Providers run on the T3 host and must be installed, authenticated, and available on
the non-interactive service user's `PATH`. Examples:

```bash
codex login
opencode auth login
command -v codex opencode
```

Do not put provider tokens in this skill or in unit files. Keep provider
authentication separate from T3 authentication.

Keep the client and server versions aligned. Use `t3 update` for the normal release
train, or `t3 update <version>` when a specific version is required. Updating restarts
the service and can interrupt active agent work; check the service afterward.

#### T3 troubleshooting

- If the service stops after logout, check `loginctl ... Linger` and
  `t3 service status`.
- If the client reports a version mismatch, update the host server to the client
  version using the upstream update instructions.
- If T3 cannot see a provider, check the service user's `PATH` and provider binary
  path; do not assume an interactive shell's version-manager setup is inherited.
- If remote access fails, verify T3 is listening on loopback, then check
  `t3 connect status` and `t3 service status`.

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
- Configure T3's OpenCode provider `Server URL` as
  `http://127.0.0.1:4096`; do not let T3 spawn a second OpenCode process.
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
- When Cloudflare Access is the authentication layer, `auth: none` is acceptable only while the service remains localhost-only. Otherwise use code-server authentication.
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
t3code.<domain>    → http://127.0.0.1:3773
```

In **Zero Trust → Access → Applications**, create a self-hosted application
covering those hostnames. Add a default-deny policy with an **Allow** rule for the
user's email identity. Enable independent MFA with TOTP and use a 7-day application
session with MFA reauthentication every 24 hours.

Keep the tunnel origins on loopback, require HTTPS at the public hostnames, and
ensure WebSockets are allowed for OpenCode, code-server, and T3. Cloudflare Access
protects the tunnel; it does not replace T3 authentication. Treat Access enrollment
links, session credentials, and tunnel tokens as
secrets.

References: [Cloudflare private applications](https://developers.cloudflare.com/cloudflare-one/setup/secure-private-apps/),
[Tunnel setup](https://developers.cloudflare.com/tunnel/get-started/).

## Maintenance

1. Run `scripts/verify.sh` before updating and record the current service/listener
   state.
2. Update one component at a time using its documented installer or package source.
   T3 uses `t3 update`; OpenCode uses the official user-local installer; preserve
   service configuration and authentication data.
3. Restart only the service affected by the update, then verify its version, health,
   and expected localhost listener.
4. Run `scripts/verify.sh` again and investigate any new warnings before updating
   another component.

Updates can interrupt active agent sessions, terminals, browser connections, or
   WebSockets. Do not print service command lines or logs that may contain tokens.
Use the upstream [T3 update documentation](https://github.com/pingdotgg/t3code/blob/main/docs/user/updating.md)
and [OpenCode installation documentation](https://opencode.ai/en/docs) for
component-specific procedures.

## Workflow

1. Run `scripts/verify.sh` and summarize the current state before changing anything.
2. Compare actual listeners, services, Docker workloads, firewall rules, and tunnel state with the preferred architecture.
3. Resolve ownership conflicts first. In particular, never allow T3 and systemd to start separate OpenCode servers on the same port.
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

Prefer public SSH key authentication or Tailscale SSH/access over password-based public SSH when the user is ready to harden the server.

## Completion criteria

A setup is healthy when:

- T3, code-server, OpenCode, Tailscale, and cloudflared services have the intended enabled/active state.
- T3 listens on `127.0.0.1:3773`.
- In standalone OpenCode mode, exactly one backend listens on `127.0.0.1:4096`.
- code-server listens on `127.0.0.1:8080`.
- Excalidraw is the expected Docker workload and publishes only `127.0.0.1:8081:80`.
- Docker has no unexplained containers, volumes, networks, or build cache.
- no secrets appear in logs, skill files, or command output copied into the repository.
