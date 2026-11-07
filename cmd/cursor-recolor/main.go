package main

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"dms-dynamic-cursor/pkg/desktop"
	"dms-dynamic-cursor/pkg/xcursor"
)

//go:embed assets/template.tar.gz
var defaultTemplate []byte

type Response struct {
	Status    string `json:"status"`
	Theme     string `json:"theme,omitempty"`
	Slot      string `json:"slot,omitempty"`
	ElapsedMs int64  `json:"elapsed_ms"`
	Error     string `json:"error,omitempty"`
}

func main() {
	start := time.Now()

	var (
		fillHex       string
		outlineHex    string
		baseName      string
		slotFlag      string
		sizeFlag      int
		apply         bool
		cleanup       bool
		fallbackTheme string
	)

	flag.StringVar(&fillHex, "fill", "#202124", "Body fill color (hex format: #RRGGBB)")
	flag.StringVar(&outlineHex, "outline", "#4c680a", "Outline accent color (hex format: #RRGGBB)")
	flag.StringVar(&baseName, "base-name", "Dux-Dynamic", "Base name for generated cursor theme")
	flag.StringVar(&slotFlag, "slot", "auto", "Theme slot: 'A', 'B', or 'auto' (flips to inactive slot)")
	flag.IntVar(&sizeFlag, "size", 0, "Cursor size in px (0 = read from DMS settings)")
	flag.BoolVar(&apply, "apply", true, "Apply theme to desktop and compositor immediately")
	flag.BoolVar(&cleanup, "cleanup", false, "Remove generated themes and restore fallback cursor theme")
	flag.StringVar(&fallbackTheme, "fallback-theme", "", "Fallback cursor theme when --cleanup is used")
	flag.Parse()

	respondErr := func(msg string) {
		resp := Response{
			Status:    "error",
			ElapsedMs: time.Since(start).Milliseconds(),
			Error:     msg,
		}
		b, _ := json.Marshal(resp)
		fmt.Println(string(b))
		os.Exit(1)
	}

	if cleanup {
		if err := desktop.Cleanup(baseName, fallbackTheme, sizeFlag); err != nil {
			respondErr(fmt.Sprintf("cleaning up cursor theme: %v", err))
		}
		resp := Response{
			Status:    "cleaned",
			Theme:     fallbackTheme,
			ElapsedMs: time.Since(start).Milliseconds(),
		}
		b, _ := json.Marshal(resp)
		fmt.Println(string(b))
		return
	}

	bodyColor, err := xcursor.ParseHexColor(fillHex)
	if err != nil {
		respondErr(fmt.Sprintf("parsing fill color: %v", err))
	}

	outlineColor, err := xcursor.ParseHexColor(outlineHex)
	if err != nil {
		respondErr(fmt.Sprintf("parsing outline color: %v", err))
	}

	home := desktop.GetUserHome()

	targetSlot := strings.ToUpper(slotFlag)
	if targetSlot == "AUTO" || targetSlot == "" {
		if desktop.ReadCurrentSlot() == "A" {
			targetSlot = "B"
		} else {
			targetSlot = "A"
		}
	}

	targetTheme := fmt.Sprintf("%s-%s", baseName, targetSlot)
	targetDir := filepath.Join(home, ".local", "share", "icons", targetTheme)

	opts := xcursor.RecolorOptions{
		BodyColor:    bodyColor,
		OutlineColor: outlineColor,
		ThemeName:    targetTheme,
		TargetDir:    targetDir,
	}

	if err := xcursor.ExtractAndRecolor(defaultTemplate, opts); err != nil {
		respondErr(fmt.Sprintf("extracting and recoloring: %v", err))
	}

	if apply {
		cursorSize := sizeFlag
		if cursorSize <= 0 {
			cursorSize = desktop.ReadDmsCursorSize()
		}

		syncOpts := desktop.SyncOptions{
			ThemeName: targetTheme,
			Size:      cursorSize,
		}

		if err := desktop.ApplyTheme(syncOpts); err != nil {
			respondErr(fmt.Sprintf("applying desktop theme: %v", err))
		}

		_ = desktop.SaveCurrentSlot(targetSlot, targetTheme)
	}

	resp := Response{
		Status:    "ok",
		Theme:     targetTheme,
		Slot:      targetSlot,
		ElapsedMs: time.Since(start).Milliseconds(),
	}
	b, _ := json.Marshal(resp)
	fmt.Println(string(b))
}
