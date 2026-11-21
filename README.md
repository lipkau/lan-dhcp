# lan-dhcp

dnsmasq as the home LAN's DHCPv4 server, with lease DNS for the names it hands out. One image,
`ghcr.io/lipkau/lan-dhcp`, runs in two places with the same configuration:

- on the Home Assistant Yellow, as the **LAN DHCP** app from this repository ([`lan_dhcp/DOCS.md`](lan_dhcp/DOCS.md));
- on the NAS, as a cold spare started by hand from `lipkau/docker.config`.

The image is dnsmasq 2.93, built from the upstream release tarball (checksum verified), and a small entrypoint. It
holds no configuration. The policy (ranges, reservations, MAC rules, options) lives in `lipkau/docker.config`, in
`spare/dhcp/config/`, and nowhere in this repository.

Only one DHCP server may serve the LAN at a time. Neither the app nor the spare starts on its own.

## Entrypoint contract

The same under Home Assistant and Docker:

| Path or variable              | Meaning                                                                                                                                             |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/config`                     | Read-only config directory. Must contain `dnsmasq.conf`, which may include other files there with `conf-file=/config/…` or `conf-dir=/config/…`.    |
| `/data`                       | Writable directory for the lease file, `/data/dnsmasq.leases`. It must exist.                                                                       |
| `/config/dnsmasq.leases.seed` | Optional. Copied to `/data/dnsmasq.leases` on a start when there is no lease file yet, to take over the leases of another DHCP server.              |
| `LAN_INTERFACE`               | The interface dnsmasq serves. Under Home Assistant, the app option `interface` (read from `/data/options.json`) is used when the variable is unset. |
| `DNSMASQ_TEST_ONLY=1`         | Stop after `dnsmasq --test`.                                                                                                                        |

The entrypoint checks that `dnsmasq.conf` exists and that the interface name is a plain Linux interface name, runs
`dnsmasq --test`, checks that `/data` and the interface exist, then runs:

```sh
dnsmasq --keep-in-foreground --log-facility=- --conf-file=/config/dnsmasq.conf \
  --interface=<name> --dhcp-leasefile=/data/dnsmasq.leases
```

Any failed check stops the container with a message. A setting in `dnsmasq.conf` overrides the command line, so
the config must not set `dhcp-leasefile` or `log-facility` to anything else.

The container starts as root so dnsmasq can bind UDP 67 and open the lease file; dnsmasq then drops to `nobody`.
It needs the host network and the `NET_ADMIN` and `NET_RAW` capabilities.

## Docker

```sh
docker run --rm --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  --mount type=bind,src=/path/to/config,dst=/config,readonly \
  --mount type=bind,src=/path/to/leases,dst=/data \
  -e LAN_INTERFACE=eth0 \
  ghcr.io/lipkau/lan-dhcp:1.0.0
```

Check a config without serving: add `-e DNSMASQ_TEST_ONLY=1` (no `/data` needed).

## Releases

The app version in [`lan_dhcp/config.yaml`](lan_dhcp/config.yaml) is the release version. Supervisor pulls
`ghcr.io/lipkau/lan-dhcp:<version>`, which only the matching release tag publishes.

1. In a pull request, bump `version` in `lan_dhcp/config.yaml` and add its entry to
   [`lan_dhcp/CHANGELOG.md`](lan_dhcp/CHANGELOG.md).
2. After it merges, tag that commit on `main` as `v<version>` and push the tag.

CI fails a tag that doesn't match the version (`scripts/check-release.sh`), so the image is never published under a
version Home Assistant won't ask for. Home Assistant offers the update as soon as `main` has the new version, so
wait for the tag's image before you update the app.

To move to a new dnsmasq release, change `DNSMASQ_VERSION` and `DNSMASQ_SHA256` in the `Dockerfile` together,
after checking the tarball's signature.

## Image

`ghcr.io/lipkau/lan-dhcp`, for `linux/amd64` and `linux/arm64`:

- `latest`: the newest release
- `1.2.3`, `1.2`, `1`: releases
- `main`: the newest build of `main`
