#!/bin/sh
# Start dnsmasq from /config/dnsmasq.conf on one LAN interface, with leases in /data.
# The same contract applies under Home Assistant and Docker; README.md describes it.
#   LAN_INTERFACE        interface to serve; else the `interface` option in /data/options.json
#   DNSMASQ_TEST_ONLY=1  stop after `dnsmasq --test`
set -eu

config=/config/dnsmasq.conf
data=/data
options=$data/options.json
leases=$data/dnsmasq.leases

die() {
    echo "lan-dhcp: $*" >&2
    exit 1
}

[ $# -eq 0 ] || die "takes no arguments; put dnsmasq options in $config"

[ -f "$config" ] || die "$config is missing: mount the config directory at /config"
[ -r "$config" ] || die "$config is not readable"

interface=${LAN_INTERFACE:-}
if [ -z "$interface" ] && [ -f "$options" ]; then
    # Supervisor writes the validated options as one JSON object; the check below rejects anything
    # that is not a plain interface name, so no JSON escapes need handling.
    interface=$(sed -n 's/.*"interface"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$options" | head -n 1)
fi

# Linux interface names have at most 15 characters.
case $interface in
    '') die "no LAN interface: set LAN_INTERFACE, or the app option interface under Home Assistant" ;;
    . | .. | *[!A-Za-z0-9_.-]*) die "invalid interface name: $interface" ;;
esac
[ ${#interface} -le 15 ] || die "interface name longer than 15 characters: $interface"

dnsmasq --test --conf-file="$config" --interface="$interface" ||
    die "$config failed dnsmasq --test"

[ "${DNSMASQ_TEST_ONLY:-}" != 1 ] || exit 0

# dnsmasq itself fails loudly when it cannot write the lease file.
[ -d "$data" ] || die "$data is missing: mount a writable directory there for $leases"
[ -e "/sys/class/net/$interface" ] || die "interface $interface does not exist on this host"

echo "lan-dhcp: serving $interface, leases in $leases"
exec dnsmasq --keep-in-foreground --log-facility=- --conf-file="$config" \
    --interface="$interface" --dhcp-leasefile="$leases"
