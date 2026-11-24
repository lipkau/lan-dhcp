#!/bin/sh
# Exercise the Ingress worker under AppArmor on a private bridge on a Linux Docker host.
set -eu

[ "$#" -eq 2 ] || { echo "usage: $0 <image> <apparmor-profile>" >&2; exit 2; }
image=$1
profile=$2
work=$(mktemp -d)
server=lan-dhcp-ingress-$$
bridge=dhcp-ci-$$
tcp_mock=$server-supervisor
socket_dir=/run/supervisor/supervisor/apps/ci_$$_lan_dhcp

# shellcheck disable=SC2329 # called by the EXIT trap
cleanup() {
    docker logs "$server" >&2 || true
    docker rm -f "$server" >/dev/null 2>&1 || true
    docker rm -f "$tcp_mock" >/dev/null 2>&1 || true
    docker network rm "$server" >/dev/null 2>&1 || true
    if [ -n "${supervisor:-}" ]; then kill "$supervisor" 2>/dev/null || true; fi
    rm -rf "$work"
    if [ -d "$socket_dir" ]; then
        rm -f "$socket_dir/supervisor.sock"
        sudo rmdir "$socket_dir"
    fi
}
trap cleanup EXIT

mkdir "$work/config" "$work/data"
# Mirror the Supervisor's host-side socket path and the app's directory mount.
sudo install -d -m 755 -o "$(id -u)" -g "$(id -g)" "$socket_dir"
cat >"$work/config/dnsmasq.conf" <<'CONF'
port=0
bind-dynamic
dhcp-range=172.30.33.100,172.30.33.150,255.255.254.0,12h
CONF
echo '4102444800 02:00:00:00:00:10 172.30.33.110 test-device *' |
    docker run --rm -i --mount "type=bind,src=$work/data,dst=/data" --entrypoint tee \
        "$image" /data/dnsmasq.leases >/dev/null

python3 - "$socket_dir/supervisor.sock" <<'PY' &
from http.server import BaseHTTPRequestHandler
from socketserver import UnixStreamServer
from os import chmod
import sys

class AppInfo(BaseHTTPRequestHandler):
    def address_string(self):
        return "localhost"

    def do_GET(self):
        responses = {
            "/info": b'{"result":"ok","data":{"supervisor":"2026.10.2"}}',
            "/addons/self/info": b'{"result":"ok","data":{"ingress_port":62042}}',
        }
        if self.path not in responses:
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(responses[self.path])

with UnixStreamServer(sys.argv[1], AppInfo) as server:
    chmod(sys.argv[1], 0o600)
    server.serve_forever()
PY
supervisor=$!
for _ in 1 2 3 4 5; do
    [ ! -S "$socket_dir/supervisor.sock" ] || break
    sleep 1
done
test -S "$socket_dir/supervisor.sock"
# HAOS Supervisor creates its per-app socket as root with mode 0600.
docker run --rm --entrypoint chown \
    --mount "type=bind,src=$socket_dir/supervisor.sock,dst=/supervisor.sock" "$image" 0:0 /supervisor.sock

docker network create --subnet 172.30.32.0/23 --gateway 172.30.32.1 \
    --opt "com.docker.network.bridge.name=$bridge" "$server" >/dev/null
start_app() {
    docker run -d --name "$server" --network host --read-only --security-opt "apparmor=$profile" \
        --cap-add NET_ADMIN --cap-add NET_RAW -e LAN_INTERFACE="$bridge" \
        --mount "type=bind,src=$work/config,dst=/config,readonly" \
        --mount "type=bind,src=$work/data,dst=/data" "$@" "$image" >/dev/null
}

start_app -e SUPERVISOR_SOCKET=/run/supervisor/api/supervisor.sock \
    --mount "type=bind,src=$socket_dir,dst=/run/supervisor/api,readonly"

url=http://172.30.32.1:62042/
check_page() {
    for _ in 1 2 3 4 5; do
        if "$@" >"$work/page" 2>"$work/client.log"; then
            break
        fi
        sleep 1
    done
    if ! grep -Fq 'test-device' "$work/page"; then
        cat "$work/client.log" >&2
        docker top "$server" -eo pid,uid,args >&2 || true
        exit 1
    fi
    grep -Fq "$bridge" "$work/page"
    test "$(curl --max-time 3 --noproxy '*' -s -o /dev/null -w '%{http_code}' "$url")" = 403
}

check_page docker run --rm --network "$server" --ip 172.30.32.2 --entrypoint wget \
    "$image" -q -T 2 -O - "$url"
docker rm -f "$server" >/dev/null

# Before Supervisor introduced per-app sockets, the app used the same endpoints over TCP.
mkdir -p "$work/api/addons/self"
echo '{"result":"ok","data":{"supervisor":"2026.10.2"}}' >"$work/api/info"
echo '{"result":"ok","data":{"ingress_port":62042}}' >"$work/api/addons/self/info"
docker run -d --name "$tcp_mock" --network "$server" --ip 172.30.32.2 --entrypoint httpd \
    --mount "type=bind,src=$work/api,dst=/api,readonly" "$image" -f -p 80 -h /api >/dev/null
start_app -e SUPERVISOR_TOKEN=test-token
check_page docker exec "$tcp_mock" wget -q -T 2 -O - "$url"
