<p align="center"><img src="lan_dhcp/logo.png" alt="LAN DHCP" width="250"></p>

# lan-dhcp

[dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) as a DHCPv4 server, packaged as a Home Assistant app and
as a container image. You write the `dnsmasq.conf`; the app adds nothing to it and hides no option behind a form.
The configuration supports tags, MAC wildcards, per-device reservations, multiple pools and lease DNS. On Home
Assistant, an AppArmor profile restricts dnsmasq’s file access and blocks external hooks.

The same image runs as the Home Assistant app and as a plain Docker container, so one configuration can serve
from either host.

> [!WARNING]
> A network may have only one DHCP server. Turn off your router's DHCP server, and any other one, before you start
> this one.

## Home Assistant app

[![Add the repository to your Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Flipkau%2Flan-dhcp)

Or add `https://github.com/lipkau/lan-dhcp` under **Settings → Apps → App store → ⋮ → Repositories**, then
install **LAN DHCP**. The [app documentation](lan_dhcp/DOCS.md) covers the setup.

## Docker

```sh
docker run -d --name lan-dhcp --network host \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --mount type=bind,src=/srv/lan-dhcp/config,dst=/config,readonly \
  --mount type=bind,src=/srv/lan-dhcp/data,dst=/data \
  -e LAN_INTERFACE=eth0 \
  ghcr.io/lipkau/lan-dhcp:1
```

To check a configuration without serving, add `-e DNSMASQ_TEST_ONLY=1`.

## Configuration

| Path or variable                              | Purpose                                                                                                                                                                                                                                                                            |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/config/dnsmasq.conf`                        | Your dnsmasq configuration, read-only. It can include other files from `/config` with `conf-file=` or `conf-dir=`.                                                                                                                                                                 |
| `/data`                                       | Writable. dnsmasq keeps its leases in `/data/dnsmasq.leases`.                                                                                                                                                                                                                      |
| `LAN_INTERFACE`                               | The interface to serve. The Home Assistant app takes it from its `interface` option.                                                                                                                                                                                               |
| `DNSMASQ_TEST_ONLY=1`                         | Run `dnsmasq --test` and exit.                                                                                                                                                                                                                                                     |
| `dnsmasq.leases.seed` in `/config` or `/data` | Optional. Leases in dnsmasq's lease format, merged on start: expired leases are dropped, then entries with a future expiry whose MAC and address no live lease holds are added. Use it to take over from another DHCP server without handing out addresses its clients still hold. |

A minimal `dnsmasq.conf` for a /24 behind a router at `192.168.1.1`:

```ini
# DHCP only; leave DNS to your existing resolver.
port=0
dhcp-authoritative
dhcp-range=192.168.1.100,192.168.1.199,255.255.255.0,12h
dhcp-option=option:router,192.168.1.1
dhcp-option=option:dns-server,192.168.1.1
```

Before it starts dnsmasq, the image checks the configuration with `dnsmasq --test`. It also refuses an interface
that doesn't exist, has no IPv4 address, or is loopback. dnsmasq starts as root to bind UDP port 67, then runs as
`nobody`. It logs to the container output. The image works with a read-only root filesystem.

## Image

`ghcr.io/lipkau/lan-dhcp` for `linux/amd64` and `linux/arm64`, with dnsmasq 2.93 built from the
[upstream release](https://thekelleys.org.uk/dnsmasq/) with a verified checksum.

| Tag                           | Meaning                                                   |
| ----------------------------- | --------------------------------------------------------- |
| `1.0.0`, `1.0`, `1`, `latest` | Releases. The Home Assistant app pulls the exact version. |
| `main`                        | The newest build of the main branch, for testing.         |

## Changelog

[`lan_dhcp/CHANGELOG.md`](lan_dhcp/CHANGELOG.md) lists the changes in each release. Home Assistant shows it on the
app's **Changelog** tab, so it lives with the app.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) explains how to build, test and release. Report security issues as
[SECURITY.md](.github/SECURITY.md) describes.

## License

[MIT](LICENSE). The image contains dnsmasq, which is licensed under the GPL.
