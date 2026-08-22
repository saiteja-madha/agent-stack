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
│   └── Tailscale Serve → private HTTPS for T3 clients
├── OpenCode            127.0.0.1:4096
│   └── Cloudflare Access/Tunnel → optional web UI
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
- Prefer Tailscale Serve for laptop/mobile T3 access.
- Verify Tailscale output says `tailnet only`; do not enable Funnel unless explicitly requested.
- Ensure systemd user lingering is enabled so the T3 user service survives logout/reboot.
- Pair each client separately; treat pairing tokens as secrets.

### OpenCode

- Use the host-native OpenCode CLI.
- Maintain exactly one OpenCode backend on `127.0.0.1:4096`.
- If a persistent OpenCode systemd service is enabled, configure T3's OpenCode provider `Server URL` to `http://127.0.0.1:4096` so T3 does not spawn a competing backend.
- Use `opencode web --hostname 127.0.0.1 --port 4096` when browser UI is desired; it also provides the backend API.
- Cloudflare Tunnel may publish the localhost service, protected by Cloudflare Access.
- If T3's `Server URL` is blank, let T3 spawn OpenCode and do not simultaneously run a separate service on port 4096.

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

Expected local service targets are:

```text
T3          http://127.0.0.1:3773   # optional Cloudflare web access
OpenCode    http://127.0.0.1:4096
code-server http://127.0.0.1:8080
Excalidraw  http://127.0.0.1:8081
```

- Prefer `127.0.0.1` over `localhost` for explicit IPv4 loopback targets.
- Do not print the cloudflared service command line if it may contain a tunnel token.
- Cloudflare Access and the application's own authentication are separate layers.

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
- exactly one OpenCode backend listens on `127.0.0.1:4096`.
- code-server listens on `127.0.0.1:8080`.
- Excalidraw is the expected Docker workload and publishes only `127.0.0.1:8081:80`.
- Tailscale Serve is private (`tailnet only`) and Funnel is not active unless intentionally enabled.
- Docker has no unexplained containers, volumes, networks, or build cache.
- no secrets appear in logs, skill files, or command output copied into the repository.
