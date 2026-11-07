package release

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

type entry struct {
	name string
	body string
	link string
	kind byte
}

func archive(t *testing.T, entries ...entry) string {
	t.Helper()
	var buffer bytes.Buffer
	gz := gzip.NewWriter(&buffer)
	writer := tar.NewWriter(gz)
	for _, e := range entries {
		kind := e.kind
		if kind == 0 {
			kind = tar.TypeReg
		}
		header := &tar.Header{Name: e.name, Mode: 0o755, Size: int64(len(e.body)), Typeflag: kind, Linkname: e.link}
		if err := writer.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if _, err := writer.Write([]byte(e.body)); err != nil {
			t.Fatal(err)
		}
	}
	writer.Close()
	gz.Close()

	path := filepath.Join(t.TempDir(), "archive.tar.gz")
	if err := os.WriteFile(path, buffer.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestExtractKeepsFilesAndLinks(t *testing.T) {
	dest := t.TempDir()
	path := archive(t,
		entry{name: "bin/heddle", body: "#!/bin/sh"},
		entry{name: "lib/libpq.so.5.17", body: "lib"},
		entry{name: "lib/libpq.so.5", kind: tar.TypeSymlink, link: "libpq.so.5.17"},
		entry{name: "bin/up", kind: tar.TypeSymlink, link: "../lib/libpq.so.5"},
	)
	if err := Extract(path, dest); err != nil {
		t.Fatal(err)
	}

	info, err := os.Stat(filepath.Join(dest, "bin", "heddle"))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm()&0o100 == 0 {
		t.Fatal("lost the executable bit")
	}
	if got, _ := os.ReadFile(filepath.Join(dest, "bin", "up")); string(got) != "lib" {
		t.Fatalf("got %q through the link", got)
	}
}

func TestExtractRefusesToLeaveItsFolder(t *testing.T) {
	cases := map[string]entry{
		"climbing":      {name: "../evil", body: "x"},
		"deep climbing": {name: "a/../../evil", body: "x"},
		"absolute":      {name: "/tmp/evil", body: "x"},
		"link out":      {name: "out", kind: tar.TypeSymlink, link: "../../etc/passwd"},
		"absolute link": {name: "out", kind: tar.TypeSymlink, link: "/etc/passwd"},
		"hard link out": {name: "out", kind: tar.TypeLink, link: "../../etc/passwd"},
	}

	for name, bad := range cases {
		t.Run(name, func(t *testing.T) {
			parent := t.TempDir()
			dest := filepath.Join(parent, "dest")
			if err := os.Mkdir(dest, 0o755); err != nil {
				t.Fatal(err)
			}

			if err := Extract(archive(t, bad), dest); err == nil {
				t.Fatal("extracted it")
			}
			if _, err := os.Lstat(filepath.Join(parent, "evil")); err == nil {
				t.Fatal("wrote outside the folder")
			}
		})
	}
}

func TestVerifiedChecksTheDownload(t *testing.T) {
	body := []byte("the program")
	sum := sha256.Sum256(body)
	good := hex.EncodeToString(sum[:]) + "  heddle.tar.gz\n"
	published := good

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if filepath.Ext(r.URL.Path) == ".sha256" {
			w.Write([]byte(published))
			return
		}
		w.Write(body)
	}))
	defer server.Close()

	dest := filepath.Join(t.TempDir(), "file")
	if err := Verified(context.Background(), server.URL+"/heddle.tar.gz", dest, nil); err != nil {
		t.Fatal(err)
	}

	published = "0000  heddle.tar.gz\n"
	if err := Verified(context.Background(), server.URL+"/heddle.tar.gz", dest, nil); err == nil {
		t.Fatal("took a damaged download")
	}
}

func TestDownloadFailsOnAMissingFile(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()

	if err := Download(context.Background(), server.URL+"/nope", filepath.Join(t.TempDir(), "f"), nil); err == nil {
		t.Fatal("a 404 isn't a download")
	}
}

func TestBaseURL(t *testing.T) {
	cases := map[[2]string]string{
		{"", ""}:                  "https://github.com/heddlehq/Heddle/releases/latest/download",
		{"0.4.6", ""}:             "https://github.com/heddlehq/Heddle/releases/download/v0.4.6",
		{"v0.4.6", ""}:            "https://github.com/heddlehq/Heddle/releases/download/v0.4.6",
		{"0.4.6", "http://m.io/"}: "http://m.io",
	}
	for input, want := range cases {
		if got := BaseURL(HeddleRepo, input[0], input[1]); got != want {
			t.Errorf("%v: got %q, want %q", input, got, want)
		}
	}
}
