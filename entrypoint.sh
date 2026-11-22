#!/bin/sh
# Start dnsmasq from /config/dnsmasq.conf on one LAN interface, with leases in /data.
# The same contract applies under Home Assistant and Docker; README.md describes it.
#   LAN_INTERFACE        interface to serve; else the `interface` option in /data/options.json
#   DNSMASQ_TEST_ONLY=1  stop after `dnsmasq --test`
# A lease seed (/config/dnsmasq.leases.seed or /data/dnsmasq.leases.seed) is merged into the
# lease file on start: entries whose MAC and address are both unknown are added.
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
[ "$interface" != lo ] || die "refusing to serve the loopback interface"
addresses=$(ip -4 -o addr show dev "$interface" | awk '{print $4}' | tr '\n' ' ')
[ -n "$addresses" ] || die "interface $interface has no IPv4 address"

# Merge lease seeds, for example the old DHCP server's leases at a cutover or a fresh export
# at a failover. Only complete lines with a future expiry and an unknown MAC and address are
# added, so a seed never overrides a lease dnsmasq handed out itself.
touch "$leases" || die "cannot create lease file $leases"
for seed in /config/dnsmasq.leases.seed "$data/dnsmasq.leases.seed"; do
    [ -f "$seed" ] || continue
    before=$(wc -l <"$leases")
    awk -v now="$(date +%s)" '
        FILENAME == ARGV[1] { mac[$2] = 1; ip[$3] = 1; next }
        NF == 5 && $1 ~ /^[0-9]+$/ && $1 > now && $2 ~ /^[0-9a-f:]+$/ && length($2) == 17 &&
            $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && !($2 in mac) && !($3 in ip) {
            print; mac[$2] = 1; ip[$3] = 1
        }
    ' "$leases" "$seed" >"$leases.merge" || die "cannot read lease seed $seed"
    cat "$leases.merge" >>"$leases" && rm -f "$leases.merge"
    echo "lan-dhcp: merged $(($(wc -l <"$leases") - before)) leases from $seed"
done

echo "lan-dhcp: serving $interface ($addresses), leases in $leases"
exec dnsmasq --keep-in-foreground --log-facility=- --pid-file --conf-file="$config" \
    --interface="$interface" --dhcp-leasefile="$leases"
