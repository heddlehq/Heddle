package treadle

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/zalando/go-keyring"
)

func TestNormalizeServer(t *testing.T) {
	cases := map[string]string{
		"localhost:4000":     "http://localhost:4000",
		" https://a.io/ ":    "https://a.io",
		"http://10.0.0.1:80": "http://10.0.0.1:80",
		"":                   "",
	}
	for input, want := range cases {
		if got := NormalizeServer(input); got != want {
			t.Errorf("%q: got %q, want %q", input, got, want)
		}
	}
}

func TestCheckTellsARefusedKey(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer good" {
			w.WriteHeader(http.StatusUnauthorized)
		}
	}))
	defer server.Close()

	if err := Check(context.Background(), server.URL, "good"); err != nil {
		t.Fatal(err)
	}
	if err := Check(context.Background(), server.URL, "bad"); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("got %v", err)
	}
}

func TestConnectSavesWhatTreadleReads(t *testing.T) {
	keyring.MockInit()
	if err := Connect("localhost:4000", "the-key"); err != nil {
		t.Fatal(err)
	}

	raw, err := keyring.Get(keyringService, keyringSession)
	if err != nil {
		t.Fatal(err)
	}
	var saved map[string]string
	if err := json.Unmarshal([]byte(raw), &saved); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"host": "http://localhost:4000", "token": "the-key", "method": "api_key"}
	for key, value := range want {
		if saved[key] != value {
			t.Errorf("%s: got %q, want %q", key, saved[key], value)
		}
	}
}

func TestConnectNeedsNoKeyring(t *testing.T) {
	keyring.MockInitWithError(errors.New("no secret service"))
	t.Cleanup(keyring.MockInit)
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("HOME", t.TempDir())

	if err := Connect("localhost:4000", "the-key"); err != nil {
		t.Fatal(err)
	}
}
