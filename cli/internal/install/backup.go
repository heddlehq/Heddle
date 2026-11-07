package install

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/heddlehq/heddle/cli/internal/config"
	"github.com/heddlehq/heddle/cli/internal/paths"
	"github.com/heddlehq/heddle/cli/internal/text"
)

// DefaultKeep is how many backups stay: a copy of the data can get big.
const DefaultKeep = 3

// Backup is a copy of the data folder.
type Backup struct {
	Name    string
	Path    string
	Created time.Time
}

// Backups lists the copies, newest first.
func Backups(layout paths.Layout) ([]Backup, error) {
	entries, err := os.ReadDir(layout.Backups())
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	backups := make([]Backup, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() || strings.HasSuffix(entry.Name(), ".partial") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			return nil, err
		}
		backups = append(backups, Backup{
			Name:    entry.Name(),
			Path:    filepath.Join(layout.Backups(), entry.Name()),
			Created: info.ModTime(),
		})
	}

	slices.SortFunc(backups, func(a, b Backup) int { return b.Created.Compare(a.Created) })
	return backups, nil
}

// CreateBackup copies the data folder. The database has to be stopped for the copy
// to be consistent, and the copy only gets its name once it's whole.
func CreateBackup(layout paths.Layout, keep int) (string, error) {
	if _, err := os.Stat(layout.Data()); errors.Is(err, os.ErrNotExist) {
		return "", nil
	}

	version := config.Version(layout)
	if version == "" {
		version = "unknown"
	}
	name := time.Now().Format("20060102-150405") + "-" + version
	partial := filepath.Join(layout.Backups(), name+".partial")

	if err := os.MkdirAll(layout.Backups(), 0o755); err != nil {
		return "", err
	}
	if err := copyTree(layout.Data(), partial); err != nil {
		_ = os.RemoveAll(partial)
		return "", fmt.Errorf("%s: %w", text.T("Could not back up your data, so nothing was changed. Is the disk full?", "Não deu para copiar seus dados, então nada foi alterado. O disco está cheio?"), err)
	}
	if err := os.Rename(partial, filepath.Join(layout.Backups(), name)); err != nil {
		return "", err
	}

	if keep > 0 {
		backups, err := Backups(layout)
		if err != nil {
			return name, err
		}
		for _, old := range backups[min(keep, len(backups)):] {
			if err := os.RemoveAll(old.Path); err != nil {
				return name, err
			}
		}
	}
	return name, nil
}

// RestoreBackup puts a copy back. The current data moves aside instead of going
// away, so a wrong choice can be undone. It returns where that went.
func RestoreBackup(layout paths.Layout, name string) (string, error) {
	source := filepath.Join(layout.Backups(), filepath.Base(name))
	if _, err := os.Stat(filepath.Join(source, "postgres", "PG_VERSION")); err != nil {
		return "", fmt.Errorf("%s: %s", text.T("This isn't a backup", "Isto não é um backup"), name)
	}

	staged := layout.Data() + ".restoring"
	_ = os.RemoveAll(staged)
	if err := copyTree(source, staged); err != nil {
		_ = os.RemoveAll(staged)
		return "", err
	}

	aside := layout.Data() + ".before-restore-" + time.Now().Format("20060102-150405")
	if err := os.Rename(layout.Data(), aside); err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	if err := os.Rename(staged, layout.Data()); err != nil {
		_ = os.Rename(aside, layout.Data())
		return "", err
	}
	return aside, nil
}

// copyTree keeps modes and links: Postgres refuses a cluster others can read.
func copyTree(source, dest string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dest, relative)

		info, err := entry.Info()
		if err != nil {
			return err
		}

		switch {
		case entry.IsDir():
			return os.MkdirAll(target, info.Mode().Perm())
		case info.Mode()&fs.ModeSymlink != 0:
			link, err := os.Readlink(path)
			if err != nil {
				return err
			}
			return os.Symlink(link, target)
		case info.Mode().IsRegular():
			return copyFile(path, target, info.Mode().Perm())
		}
		return nil
	})
}

func copyFile(source, dest string, mode fs.FileMode) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()

	output, err := os.OpenFile(dest, os.O_CREATE|os.O_WRONLY|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(output, input); err != nil {
		output.Close()
		return err
	}
	return output.Close()
}
