#!/bin/sh
# Exercise the Ingress worker under AppArmor on a private bridge on a Linux Docker host.
set -eu

[ "$#" -eq 2 ] || { echo "usage: $0 <image> <apparmor-profile>" >&2; exit 2; }
image=$1
profile=$2
work=$(mktemp -d)
server=lan-dhcp-ingress-$$
bridge=dhcp-ci-$$

# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
    docker logs "$server" >&2 || true
    docker rm -f "$server" >/dev/null 2>&1 || true
    docker network rm "$server" >/dev/null 2>&1 || true
    if [ -n "${supervisor:-}" ]; then kill "$supervisor" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT

mkdir "$work/config" "$work/data"
cat >"$work/config/dnsmasq.conf" <<'CONF'
port=0
bind-dynamic
dhcp-range=172.30.33.100,172.30.33.150,255.255.254.0,12h
CONF
echo '4102444800 02:00:00:00:00:10 172.30.33.110 test-device *' >"$work/data/dnsmasq.leases"

python3 - "$work/supervisor.sock" <<'PY' &
from http.server import BaseHTTPRequestHandler
from socketserver import UnixStreamServer
import sys

class AppInfo(BaseHTTPRequestHandler):
    def address_string(self):
        return "localhost"

    def do_GET(self):
        if self.path != "/addons/self/info":
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"result":"ok","data":{"ingress_port":62042}}')

with UnixStreamServer(sys.argv[1], AppInfo) as server:
    server.serve_forever()
PY
supervisor=$!
for _ in 1 2 3 4 5; do
    [ ! -S "$work/supervisor.sock" ] || break
    sleep 1
done
test -S "$work/supervisor.sock"

docker network create --subnet 172.30.32.0/23 --gateway 172.30.32.1 \
    --opt "com.docker.network.bridge.name=$bridge" "$server" >/dev/null
docker run -d --name "$server" --network host --read-only --security-opt "apparmor=$profile" \
    --cap-add NET_ADMIN --cap-add NET_RAW -e LAN_INTERFACE="$bridge" \
    -e SUPERVISOR_SOCKET=/run/supervisor/api/supervisor.sock \
    --mount "type=bind,src=$work/supervisor.sock,dst=/run/supervisor/api/supervisor.sock,readonly" \
    --mount "type=bind,src=$work/config,dst=/config,readonly" \
    --mount "type=bind,src=$work/data,dst=/data" "$image" >/dev/null

url=http://172.30.32.1:62042/
for _ in 1 2 3 4 5; do
    if docker run --rm --network "$server" --ip 172.30.32.2 --entrypoint wget \
        "$image" -q -T 2 -O - "$url" >"$work/page" 2>"$work/client.log"; then
        break
    fi
    sleep 1
done
grep -Fq 'test-device' "$work/page" || { cat "$work/client.log" >&2; exit 1; }
grep -Fq "$bridge" "$work/page"
test "$(curl --max-time 3 --noproxy '*' -s -o /dev/null -w '%{http_code}' "$url")" = 403
