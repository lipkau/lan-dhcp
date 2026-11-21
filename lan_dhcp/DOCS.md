# LAN DHCP

Runs dnsmasq as the home LAN's DHCPv4 server, with lease DNS for the names it hands out. The app adds no settings
of its own: dnsmasq reads the `dnsmasq.conf` you put in the app config folder.

## Never run two DHCP servers

Only one DHCP server may serve the LAN. Before you start this app, turn off every other one: the router's DHCP
server, AdGuard Home's DHCP server, and the spare container on the NAS. Before another server takes over, stop
this app.

So the app starts only when you start it: it doesn't start on boot until you turn on **Start on boot**. Turn that
on only while this app is the LAN's DHCP server.

## Install

1. Open the app store in **Settings**, choose **Repositories** from its menu, and add
   `https://github.com/lipkau/lan-dhcp`.
2. Install **LAN DHCP**. Don't start it yet.

## Configure

1. Put `dnsmasq.conf` in the app config folder. The Samba and SSH apps show it as
   `addon_configs/<repository id>_lan_dhcp/`; Supervisor creates it when you install the app. dnsmasq reads it
   as `/config/dnsmasq.conf`, read-only.
2. `dnsmasq.conf` may include other files from the same folder with `conf-file=/config/<file>` or
   `conf-dir=/config/<folder>`. Refer to them by their `/config` path.
3. Set the `interface` option to the LAN interface of the Home Assistant host (`end0` on a Home Assistant
   Yellow). **Settings → System → Network** lists the interfaces.

The policy itself, with its ranges, reservations and options, is kept in `lipkau/docker.config`
(`spare/dhcp/config/`). Copy it from there.

## Options

| Option      | Default | Meaning                                                                                       |
| ----------- | ------- | --------------------------------------------------------------------------------------------- |
| `interface` | `end0`  | The network interface dnsmasq serves. Letters, digits, `.`, `_` and `-`, up to 15 characters. |

## Leases

dnsmasq keeps its leases in the app's data folder, as `/data/dnsmasq.leases`. They survive restarts and updates;
uninstalling the app deletes them. Don't set `dhcp-leasefile` in `dnsmasq.conf`.

To take over from another DHCP server, put its leases in dnsmasq's lease format into the app config folder as
`dnsmasq.leases.seed` before the first start. The app copies them while it has no lease file of its own, then ignores
the seed. Remove it once the cutover is done.

## Start and logs

When it starts, the app checks the interface name, runs `dnsmasq --test` on the config, then starts dnsmasq.
A missing `dnsmasq.conf`, an invalid interface or a config error stops it with a message in the log. dnsmasq logs
to the app log.
