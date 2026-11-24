# LAN DHCP

Runs [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html) as the DHCPv4 server for your network. dnsmasq
reads a `dnsmasq.conf` that you write; the app adds nothing to it.

## Before you start

A network may have only one DHCP server. Before you start this app, turn off the DHCP server in your router, the
one in AdGuard Home if you use it, and any other. Two servers answering the same request leave devices with
conflicting addresses.

The app therefore doesn't start on its own. It runs only after you start it, and starts on boot only after you turn
on **Start on boot**. Turn that on once this app is your network's DHCP server.

## Install

1. Add the repository: **Settings → Apps → App store → ⋮ → Repositories**, enter
   `https://github.com/lipkau/lan-dhcp`.
2. Install **LAN DHCP**. Don't start it yet.

## Configure

1. Set the **Network interface** option to the interface of this host that is connected to your network, for example
   `end0` on a Home Assistant Yellow. **Settings → System → Network** lists the interfaces.
2. Put your `dnsmasq.conf` into the app's configuration folder. The Samba share shows it as
   `addon_configs/<id>_lan_dhcp`. Home Assistant creates the folder when you install the app. dnsmasq reads it as
   `/config`, so refer to other files there by that path, for example `conf-file=/config/reservations.conf`.

A minimal configuration for a /24 behind a router at `192.168.1.1`:

```ini
# DHCP only; leave DNS to your existing resolver.
port=0
dhcp-authoritative
dhcp-range=192.168.1.100,192.168.1.199,255.255.255.0,12h
dhcp-option=option:router,192.168.1.1
dhcp-option=option:dns-server,192.168.1.1
```

The [dnsmasq manual](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) lists every option. Leave out
`dhcp-leasefile`, `log-facility` and `pid-file`: the app sets them.

## Start

Start the app and open its log. On a good start it shows the interface with its address, any merged leases, and the
DHCP ranges dnsmasq serves. It stops with a message in the log if:

- `dnsmasq.conf` is missing or fails `dnsmasq --test`,
- the interface doesn't exist, has no IPv4 address, or is loopback.

Then connect a device and check it gets an address from the expected range.

## Leases

dnsmasq keeps its leases in the app's data folder. They survive restarts and updates; uninstalling the app deletes
them.

To take over from another DHCP server without handing out addresses its clients still hold, export its leases in
dnsmasq's lease format to `dnsmasq.leases.seed` in the configuration folder and start the app. On every start it
drops its expired leases, then adds the seed's entries that expire in the future and whose MAC and address no live
lease holds, so a seed never overrides a lease the app handed out. Delete the seed once its leases have expired.

## AppArmor

On Home Assistant OS, the app's AppArmor profile allows reads from `/config` and limits writes to the
lease files in `/data`. Keep included configuration and data files such as host lists under `/config`.
Lease hooks that execute external programs and options that write to other paths are blocked.

## Support

Report problems in the [issue tracker](https://github.com/lipkau/lan-dhcp/issues).
