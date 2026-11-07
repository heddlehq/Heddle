// Package release fetches what the GitHub releases publish: it finds versions,
// downloads with progress, checks checksums and unpacks archives.
package release

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/heddlehq/heddle/cli/internal/text"
)

const (
	HeddleRepo  = "heddlehq/Heddle"
	TreadleRepo = "heddlehq/Treadle"
)

// BaseURL is the folder a version's files are downloaded from. override comes from
// HEDDLE_DOWNLOAD_URL or TREADLE_DOWNLOAD_URL, for a mirror.
func BaseURL(repo, version, override string) string {
	if override != "" {
		return strings.TrimRight(override, "/")
	}
	if version == "" || version == "latest" {
		return "https://github.com/" + repo + "/releases/latest/download"
	}
	return "https://github.com/" + repo + "/releases/download/v" + strings.TrimPrefix(version, "v")
}

// Latest asks GitHub for the newest version. It follows the redirect of the latest
// release page, which has no API rate limit.
func Latest(ctx context.Context, repo string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	request, err := http.NewRequestWithContext(ctx, http.MethodHead, "https://github.com/"+repo+"/releases/latest", nil)
	if err != nil {
		return "", err
	}

	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()

	location := response.Header.Get("Location")
	if location == "" {
		return "", fmt.Errorf("GitHub answered %s", response.Status)
	}
	return strings.TrimPrefix(path.Base(location), "v"), nil
}

// Versions lists the newest published versions, newest first.
func Versions(ctx context.Context, repo string, limit int) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	target := fmt.Sprintf("https://api.github.com/repos/%s/releases?per_page=%d", repo, limit)
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("Accept", "application/vnd.github+json")

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GitHub answered %s", response.Status)
	}

	var releases []struct {
		Tag        string `json:"tag_name"`
		Draft      bool   `json:"draft"`
		Prerelease bool   `json:"prerelease"`
	}
	if err := json.NewDecoder(response.Body).Decode(&releases); err != nil {
		return nil, err
	}

	versions := make([]string, 0, len(releases))
	for _, release := range releases {
		if !release.Draft && !release.Prerelease {
			versions = append(versions, strings.TrimPrefix(release.Tag, "v"))
		}
	}
	return versions, nil
}

// Progress hears how much of a download has arrived. total is 0 when the server
// doesn't say.
type Progress func(done, total int64)

// Download saves a URL to a file.
func Download(ctx context.Context, url, dest string, progress Progress) error {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("%s answered %s", url, response.Status)
	}

	file, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer file.Close()

	var reader io.Reader = response.Body
	if progress != nil {
		reader = &countingReader{reader: reader, total: response.ContentLength, progress: progress}
	}
	if _, err := io.Copy(file, reader); err != nil {
		return err
	}
	return file.Close()
}

type countingReader struct {
	reader   io.Reader
	done     int64
	total    int64
	progress Progress
	reported time.Time
}

func (c *countingReader) Read(buffer []byte) (int, error) {
	n, err := c.reader.Read(buffer)
	c.done += int64(n)

	// Often enough to look alive, and not so often it slows the download down.
	if err != nil || time.Since(c.reported) > 50*time.Millisecond {
		c.reported = time.Now()
		c.progress(c.done, c.total)
	}
	return n, err
}

// Verified downloads a file and the .sha256 published next to it, and fails when
// they don't match.
func Verified(ctx context.Context, url, dest string, progress Progress) error {
	if err := Download(ctx, url, dest, progress); err != nil {
		return err
	}
	if err := Download(ctx, url+".sha256", dest+".sha256", nil); err != nil {
		return err
	}
	defer os.Remove(dest + ".sha256")

	raw, err := os.ReadFile(dest + ".sha256")
	if err != nil {
		return err
	}
	return Check(dest, string(raw))
}

// Check compares a file with the first word of a sha256sum line.
func Check(file, sum string) error {
	fields := strings.Fields(sum)
	if len(fields) == 0 {
		return errors.New(text.T("The checksum file is empty.", "O arquivo de checksum está vazio."))
	}

	handle, err := os.Open(file)
	if err != nil {
		return err
	}
	defer handle.Close()

	hash := sha256.New()
	if _, err := io.Copy(hash, handle); err != nil {
		return err
	}
	if !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), fields[0]) {
		return errors.New(text.T("The download is damaged. Run the installer again.", "O download veio corrompido. Rode o instalador de novo."))
	}
	return nil
}

// Extract unpacks a .tar.gz into dest, refusing anything that would land outside.
func Extract(archive, dest string) error {
	file, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer file.Close()

	gz, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gz.Close()

	root, err := filepath.Abs(dest)
	if err != nil {
		return err
	}

	reader := tar.NewReader(gz)
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := extractEntry(reader, header, root); err != nil {
			return err
		}
	}
}

func extractEntry(reader io.Reader, header *tar.Header, root string) error {
	target, err := inside(root, header.Name)
	if err != nil {
		return err
	}

	switch header.Typeflag {
	case tar.TypeDir:
		return os.MkdirAll(target, 0o755)
	case tar.TypeReg:
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		file, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, header.FileInfo().Mode().Perm()|0o200)
		if err != nil {
			return err
		}
		if _, err := io.Copy(file, reader); err != nil {
			file.Close()
			return err
		}
		return file.Close()
	case tar.TypeSymlink:
		// A link may climb, as long as where it lands is still inside.
		if filepath.IsAbs(header.Linkname) || !within(root, filepath.Join(filepath.Dir(target), header.Linkname)) {
			return fmt.Errorf("the archive links outside its folder: %s", header.Name)
		}
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return err
		}
		_ = os.Remove(target)
		return os.Symlink(header.Linkname, target)
	case tar.TypeLink:
		source, err := inside(root, header.Linkname)
		if err != nil {
			return err
		}
		_ = os.Remove(target)
		return os.Link(source, target)
	default:
		return nil
	}
}

func inside(root, name string) (string, error) {
	if filepath.IsAbs(name) {
		return "", fmt.Errorf("the archive has an absolute path: %s", name)
	}
	target := filepath.Join(root, name)
	if !within(root, target) {
		return "", fmt.Errorf("the archive leaves its folder: %s", name)
	}
	return target, nil
}

func within(root, target string) bool {
	relative, err := filepath.Rel(root, target)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))
}
