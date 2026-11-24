package main

import (
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestActiveLeases(t *testing.T) {
	now := time.Unix(1800000000, 0)
	contents := `1800003600 02:00:00:00:00:01 192.0.2.100 tablet *
0 02:00:00:00:00:02 192.0.2.101 * *
1799999999 02:00:00:00:00:03 192.0.2.102 expired *
1800003600 02:00:00:00:00:04 2001:db8::100 ipv6 *
duid 00:00
1800003600 02:00:00:00:00:05 192.0.2.105 incomplete`
	leases, err := activeLeases(strings.NewReader(contents), now)
	if err != nil || len(leases) != 2 {
		t.Fatalf("activeLeases() = %#v, %v", leases, err)
	}
	if leases[0].Address.String() != "192.0.2.100" || leases[0].Hostname != "tablet" ||
		leases[0].Expires != now.Add(time.Hour).UTC().Format("2006-01-02 15:04") {
		t.Errorf("timed lease = %#v", leases[0])
	}
	if leases[1].Hostname != "" || leases[1].Expires != "Never" {
		t.Errorf("indefinite lease = %#v", leases[1])
	}
}

func TestLeasePage(t *testing.T) {
	leases, err := os.CreateTemp(t.TempDir(), "leases")
	if err != nil {
		t.Fatal(err)
	}
	defer leases.Close()
	if _, err := leases.WriteString("0 02:00:00:00:00:01 192.0.2.100 <unsafe> *\n"); err != nil {
		t.Fatal(err)
	}
	handler := leaseHandler("end0", leases)
	cases := []struct {
		name   string
		method string
		path   string
		peer   string
		want   int
	}{
		{"Supervisor GET", http.MethodGet, "/", supervisorIP, http.StatusOK},
		{"Supervisor HEAD", http.MethodHead, "/", supervisorIP, http.StatusOK},
		{"direct request", http.MethodGet, "/", "192.0.2.50", http.StatusForbidden},
		{"write request", http.MethodPost, "/", supervisorIP, http.StatusMethodNotAllowed},
		{"unknown path", http.MethodGet, "/data", supervisorIP, http.StatusNotFound},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(tc.method, tc.path, nil)
			req.RemoteAddr = tc.peer + ":1234"
			req.Header.Set("X-Forwarded-For", supervisorIP)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != tc.want {
				t.Fatalf("HTTP status = %d, want %d", res.Code, tc.want)
			}
			body := res.Body.String()
			if tc.want == http.StatusOK && tc.method == http.MethodGet {
				for _, want := range []string{"end0", "192.0.2.100", "&lt;unsafe&gt;"} {
					if !strings.Contains(body, want) {
						t.Errorf("page does not contain %q", want)
					}
				}
				if res.Header().Get("Cache-Control") != "no-store" {
					t.Error("lease page must not be cached")
				}
			} else if strings.Contains(body, "192.0.2.100") {
				t.Error("response exposed lease data")
			}
		})
	}
}

func TestDiscoverIngressPort(t *testing.T) {
	cases := []struct {
		version string
		body    string
		want    int
	}{
		{"2026.10.2", `{"result":"ok","data":{"ingress_port":8099}}`, 8099},
		{"2026.11.0", `{"result":"ok","data":{"ingress_port":0}}`, 0},
		{"2026.11.0", `{"result":"error","data":{"ingress_port":62042}}`, 0},
		{"2026.10.1", `{"result":"ok","data":{"ingress_port":62042}}`, 0},
		{"2026.10.2.dev1", `{"result":"ok","data":{"ingress_port":62042}}`, 0},
	}
	for _, tc := range cases {
		t.Run(tc.version+" "+tc.body, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") != "Bearer test-token" {
					t.Error("Supervisor request missing token")
				}
				switch r.URL.Path {
				case "/info":
					_, _ = fmt.Fprintf(w, `{"result":"ok","data":{"supervisor":%q}}`, tc.version)
				case "/addons/self/info":
					_, _ = io.WriteString(w, tc.body)
				default:
					t.Errorf("unexpected Supervisor request %s", r.URL.Path)
					w.WriteHeader(http.StatusNotFound)
				}
			}))
			defer server.Close()
			got, err := discoverIngressPort(server.Client(), server.URL, "test-token")
			if got != tc.want || (err == nil) != (tc.want != 0) {
				t.Errorf("discoverIngressPort() = %d, %v, want %d", got, err, tc.want)
			}
		})
	}
}
