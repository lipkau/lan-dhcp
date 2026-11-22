# lan-dhcp

A Home Assistant app repository and container image that run dnsmasq from a user-supplied `dnsmasq.conf`.
[CONTRIBUTING.md](CONTRIBUTING.md) has the layout, the commands to validate a change, and the release steps; CI
(`.github/workflows/ci.yml`) runs the same checks.

## Rules

- No site configuration in this repository. The owner's network policy lives in the private `lipkau/docker.config`
  (`spare/dhcp/config/`), which also deploys this image as a spare. `tests/config/` is a fixture on a test subnet.
- The contract in the README (`/config`, `/data`, `LAN_INTERFACE`, lease seeds) is shared by the Home Assistant app
  and Docker. Changing it changes both deployments.
- Fail loudly. A DHCP server that starts on the wrong interface or with a broken config is worse than one that
  doesn't start.
- Keep `boot: manual` in `lan_dhcp/config.yaml`: two DHCP servers must never serve one network.
- The container starts as root on purpose; dnsmasq drops to `nobody` after binding UDP 67.
- Every merge that changes `lan_dhcp/` releases. Never bump `version` or add a `lan_dhcp/CHANGELOG.md` entry in a
  pull request; CI's release job writes both. Commit subjects and pull request titles are conventional commits,
  because they set the version and become the changelog.
