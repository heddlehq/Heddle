package brand

import (
	"slices"
	"testing"

	"github.com/charmbracelet/x/ansi"
)

func TestWovenKeepsItsSizeAllTheWay(t *testing.T) {
	for _, fraction := range []float64{-1, 0, 0.1, 0.25, 0.5, 0.9, 1, 2} {
		rows := Woven(fraction)
		if len(rows) != len(mark)/2 {
			t.Fatalf("%v: %d rows", fraction, len(rows))
		}
		for _, row := range rows {
			if width := ansi.StringWidth(row); width != MarkWidth {
				t.Fatalf("%v: width %d", fraction, width)
			}
		}
	}
}

func TestTheWeavingChangesAsItAdvances(t *testing.T) {
	if slices.Equal(Woven(0), Woven(1)) {
		t.Fatal("the start looks like the end")
	}
}
