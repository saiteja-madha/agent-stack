# Traefik templates

Render these templates into `INFRA_ROOT`; do not edit them with real domains,
hostnames, identities, addresses, or secrets in the skill repository.

- `compose.yml` deploys the shared reverse proxy.
- `docker-service.compose.yml` is the preferred publishing pattern.
- `host-route.yml` supports a host-native origin that is reachable from the
  Traefik container through an explicitly approved private address.

Before publishing, collect `PROJECT_DOMAIN`, route name, service name, and internal
port. Validate the rendered Compose or dynamic configuration and verify that an
unknown hostname still returns 404.
