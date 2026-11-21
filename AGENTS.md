# lan-dhcp

The dnsmasq image that serves DHCPv4 and lease DNS on the home LAN, and the Home Assistant app repository that
installs it on the Yellow (`repository.yaml`, `lan_dhcp/`). The NAS runs the same image as a cold spare from
`lipkau/docker.config`. `README.md` covers the entrypoint contract and releases.

## Validate

Run these before committing; CI runs the same:

- `npm ci && npx biome ci` (Markdown)
- `shellcheck entrypoint.sh tests/run.sh scripts/*.sh`
- `scripts/check-release.sh`
- `docker build -t lan-dhcp:test . && tests/run.sh lan-dhcp:test` (needs Docker; it creates and removes a
  private Docker network for a DHCP exchange)

## Rules

- No policy here. Ranges, reservations, MAC rules and DHCP options live in `lipkau/docker.config`
  (`spare/dhcp/config/`). `tests/config/` is a test fixture on a private test subnet, not the LAN policy.
- Keep the entrypoint contract in `README.md` identical for Home Assistant and Docker. A change to it is a change
  to both deployments and to `docker.config`.
- Fail loudly: a DHCP server that starts with the wrong config or interface is worse than one that doesn't start.
- The container starts as root on purpose; dnsmasq drops to `nobody` after binding UDP 67.
- Change `DNSMASQ_VERSION` and `DNSMASQ_SHA256` together, from a checksum you verified against the upstream
  signature.
- Two DHCP servers must never serve the LAN: keep `boot: manual` in `lan_dhcp/config.yaml`.
- `version` in `lan_dhcp/config.yaml` is the release version. Bump it with a `lan_dhcp/CHANGELOG.md` entry, then
  tag `v<version>` on `main`.

## Images

CI publishes `ghcr.io/lipkau/lan-dhcp`; `.github/workflows/ci.yml` defines the tags.
This repository only publishes images. The deployment lives in `lipkau/docker.config`; the Home Assistant app pulls
the release image.
