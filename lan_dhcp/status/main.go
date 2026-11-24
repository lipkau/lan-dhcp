package main

import (
	"bufio"
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"log"
	"net"
	"net/http"
	"net/netip"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	supervisorIP = "172.30.32.2"
	ingressHost  = "172.30.32.1" // Supervisor connects to its bridge gateway for host-network apps.
)

//go:embed status.html
var statusHTML string
var statusPage = template.Must(template.New("status").Parse(statusHTML))

func main() {
	if len(os.Args) == 2 && os.Args[1] == "ingress-port" {
		port, err := supervisorPort()
		if err != nil {
			log.Fatalf("LAN DHCP status: %v", err)
		}
		fmt.Println(port)
		return
	}
	if len(os.Args) != 3 {
		log.Fatal("usage: lan-dhcp-status <port> <interface>")
	}

	// The entrypoint opens the active lease file after merging any seed. dnsmasq
	// updates that inode in place. The status process only receives a read descriptor.
	leases := os.NewFile(3, "dnsmasq.leases")
	info, err := leases.Stat()
	if err != nil || !info.Mode().IsRegular() {
		log.Fatal("LAN DHCP status: missing lease file descriptor")
	}
	server := &http.Server{
		Handler:           leaseHandler(os.Args[2], leases),
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       30 * time.Second,
		MaxHeaderBytes:    16 << 10,
	}
	listener, err := net.Listen("tcp4", net.JoinHostPort(ingressHost, os.Args[1]))
	if err != nil {
		log.Fatalf("LAN DHCP status: %v", err)
	}
	log.Fatal(server.Serve(listener))
}

type lease struct {
	Address  netip.Addr
	MAC      string
	Hostname string
	Expires  string
}

func activeLeases(reader io.Reader, now time.Time) ([]lease, error) {
	var leases []lease
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) != 5 {
			continue
		}
		expires, err := strconv.ParseInt(fields[0], 10, 64)
		if err != nil || (expires != 0 && expires <= now.Unix()) {
			continue
		}
		ip, err := netip.ParseAddr(fields[2])
		if err != nil || !ip.Is4() {
			continue
		}
		item := lease{Address: ip, MAC: fields[1], Hostname: fields[3], Expires: "Never"}
		if item.Hostname == "*" {
			item.Hostname = ""
		}
		if expires != 0 {
			item.Expires = time.Unix(expires, 0).UTC().Format("2006-01-02 15:04")
		}
		leases = append(leases, item)
	}
	return leases, scanner.Err()
}

func leaseHandler(iface string, file io.ReaderAt) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil || host != supervisorIP {
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			w.Header().Set("Allow", "GET, HEAD")
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'self'; form-action 'none'")
		w.Header().Set("X-Content-Type-Options", "nosniff")

		// A SectionReader gives concurrent requests independent offsets.
		leases, err := activeLeases(io.NewSectionReader(file, 0, 4<<20), time.Now())
		if err != nil {
			http.Error(w, "Could not read the lease file", http.StatusServiceUnavailable)
			return
		}
		var page bytes.Buffer
		if err := statusPage.Execute(&page, struct {
			Interface string
			Leases    []lease
		}{iface, leases}); err != nil {
			log.Printf("LAN DHCP status: render leases: %v", err)
			http.Error(w, "Could not display leases", http.StatusInternalServerError)
			return
		}
		if r.Method == http.MethodGet {
			_, _ = page.WriteTo(w)
		}
	})
}

func supervisorPort() (int, error) {
	transport := &http.Transport{}
	token := os.Getenv("SUPERVISOR_TOKEN")
	if socket := os.Getenv("SUPERVISOR_SOCKET"); socket != "" {
		transport.DialContext = func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socket)
		}
		token = "" // Supervisor authenticates callers on the per-app socket.
	}
	client := &http.Client{
		Transport:     transport,
		Timeout:       5 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
	return discoverIngressPort(client, "http://"+supervisorIP, token)
}

func discoverIngressPort(client *http.Client, baseURL, token string) (int, error) {
	system, err := readSupervisorInfo(client, baseURL+"/info", token)
	if err != nil {
		return 0, err
	}
	if !supportsAdminIngress(system.Version) {
		return 0, fmt.Errorf("the lease page requires Supervisor 2026.10.2 or newer")
	}
	app, err := readSupervisorInfo(client, baseURL+"/addons/self/info", token)
	if err != nil {
		return 0, err
	}
	if app.Port < 62000 || app.Port > 65535 {
		return 0, fmt.Errorf("Supervisor did not assign an ingress port")
	}
	return app.Port, nil
}

func supportsAdminIngress(version string) bool {
	// Supervisor 2026.10.2 began enforcing panel_admin on sessions.
	var year, month, patch int
	if _, err := fmt.Sscanf(version, "%d.%d.%d", &year, &month, &patch); err != nil {
		return false
	}
	return year > 2026 || year == 2026 && (month > 10 || month == 10 && (patch > 2 || patch == 2 && version == "2026.10.2"))
}

type supervisorInfo struct {
	Version string `json:"supervisor"`
	Port    int    `json:"ingress_port"`
}

func readSupervisorInfo(client *http.Client, endpoint, token string) (supervisorInfo, error) {
	req, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return supervisorInfo{}, err
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := client.Do(req)
	if err != nil {
		return supervisorInfo{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return supervisorInfo{}, fmt.Errorf("Supervisor %s returned HTTP %d", req.URL.Path, resp.StatusCode)
	}
	var info struct {
		Result string
		Data   supervisorInfo
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&info); err != nil {
		return supervisorInfo{}, fmt.Errorf("read Supervisor %s: %w", req.URL.Path, err)
	}
	if info.Result != "ok" {
		return supervisorInfo{}, fmt.Errorf("Supervisor %s returned %q", req.URL.Path, info.Result)
	}
	return info.Data, nil
}
