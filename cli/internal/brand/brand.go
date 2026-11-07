// Package brand holds the palette and the woven logo. The colors are the dark
// theme of the web app, and match internal/tui/styles.go and brand.go in Treadle.
package brand

import (
	"image/color"
	"strings"

	"charm.land/lipgloss/v2"
)

var (
	Ink     = lipgloss.Color("#23262b")
	Deep    = lipgloss.Color("#181a1e")
	Raised  = lipgloss.Color("#33363c")
	Border  = lipgloss.Color("#4a4d54")
	Dim     = lipgloss.Color("#5a5c60")
	Paper   = lipgloss.Color("#f3ebdc")
	Muted   = lipgloss.Color("#aca391")
	Accent  = lipgloss.Color("#e8907d")
	Ribbon  = lipgloss.Color("#a63a2b")
	Warm    = lipgloss.Color("#e8b77d")
	Success = lipgloss.Color("#2fb5a5")
	Danger  = lipgloss.Color("#f0788a")
)

// The logo is woven: the coral weft passes over and under the cream warps, and the
// one-pixel gaps show which is on top. '#' is warp, 'o' is weft.
var mark = []string{
	".....##........##......",
	"....####......####.....",
	"....####......####.....",
	"....####......####.....",
	"....####......####.....",
	"....####......####.....",
	"..............####.....",
	".oooooooooooo.####.ooo.",
	"ooooooooooooo.####.oooo",
	"ooooooooooooo.####.oooo",
	".oooooooooooo.####.ooo.",
	"..............####.....",
	"....####......####.....",
	"....####......####.....",
	"....####......####.....",
	"....####......####.....",
	"....####......####.....",
	".....##........##......",
}

var treadleMark = []string{
	"...........##...........",
	"..........####..........",
	"..........####..........",
	".oooooooo.####.oooooooo.",
	"ooooooooo.####.ooooooooo",
	"ooooooooo.####.ooooooooo",
	".oooooooo.####.oooooooo.",
	"..........####..........",
	"..........####..........",
	"..........####..........",
	"..........####..........",
	"..........####..........",
	"..........####..........",
	"..........####..........",
	"..........####..........",
	"...........##...........",
}

// MarkWidth is the width of the logo in terminal cells.
var MarkWidth = len(mark[0])

// Woven draws the Heddle logo as far as the weaving has gone, from 0 to 1.
func Woven(fraction float64) []string { return weave(mark, fraction) }

// WovenTreadle draws the Treadle logo the same way.
func WovenTreadle(fraction float64) []string { return weave(treadleMark, fraction) }

// weave puts the warps up first, as on a loom, and the weft then crosses them with
// the shuttle at its head.
func weave(mark []string, fraction float64) []string {
	fraction = min(max(fraction, 0), 1)

	width := len(mark[0])
	warpRows := int(min(fraction/0.25, 1) * float64(len(mark)))
	weftColumns := int(max(fraction-0.25, 0) / 0.75 * float64(width))

	pixels := make([][]color.Color, len(mark))
	for y, row := range mark {
		pixels[y] = make([]color.Color, width)
		for x, pixel := range row {
			switch pixel {
			case '#':
				pixels[y][x] = Dim
				if len(mark)-y <= warpRows {
					pixels[y][x] = Paper
				}
			case 'o':
				switch {
				case x < weftColumns:
					pixels[y][x] = Accent
				case x == weftColumns && fraction < 1 && fraction > 0.25:
					pixels[y][x] = Warm
				default:
					pixels[y][x] = Raised
				}
			}
		}
	}
	return renderPixels(pixels)
}

// renderPixels draws two pixels per cell, so the art stays square in a terminal.
func renderPixels(pixels [][]color.Color) []string {
	rows := make([]string, 0, (len(pixels)+1)/2)
	for y := 0; y < len(pixels); y += 2 {
		var b strings.Builder
		for x := range pixels[y] {
			var bottom color.Color
			if y+1 < len(pixels) {
				bottom = pixels[y+1][x]
			}
			b.WriteString(pixelPair(pixels[y][x], bottom))
		}
		rows = append(rows, b.String())
	}
	return rows
}

func pixelPair(top, bottom color.Color) string {
	switch {
	case top == nil && bottom == nil:
		return " "
	case top == nil:
		return lipgloss.NewStyle().Foreground(bottom).Render("▄")
	case bottom == nil:
		return lipgloss.NewStyle().Foreground(top).Render("▀")
	case top == bottom:
		return lipgloss.NewStyle().Foreground(top).Render("█")
	default:
		return lipgloss.NewStyle().Foreground(top).Background(bottom).Render("▀")
	}
}
