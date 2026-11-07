package xcursor

import (
	"image/color"
	"os"
	"path/filepath"
	"testing"
)

func TestParseHexColor(t *testing.T) {
	tests := []struct {
		input    string
		expected color.RGBA
		wantErr  bool
	}{
		{"#ffffff", color.RGBA{255, 255, 255, 255}, false},
		{"000000", color.RGBA{0, 0, 0, 255}, false},
		{"#4c680a", color.RGBA{0x4c, 0x68, 0x0a, 255}, false},
		{"#xyz", color.RGBA{}, true},
		{"12345", color.RGBA{}, true},
	}

	for _, tt := range tests {
		got, err := ParseHexColor(tt.input)
		if (err != nil) != tt.wantErr {
			t.Errorf("ParseHexColor(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			continue
		}
		if !tt.wantErr && got != tt.expected {
			t.Errorf("ParseHexColor(%q) = %v, want %v", tt.input, got, tt.expected)
		}
	}
}

func TestExtractAndRecolor(t *testing.T) {
	templatePath := "../../cmd/cursor-recolor/assets/template.tar.gz"
	templateBytes, err := os.ReadFile(templatePath)
	if err != nil {
		t.Skipf("template archive not found at %s: %v", templatePath, err)
	}

	tempDir, err := os.MkdirTemp("", "cursor-test-*")
	if err != nil {
		t.Fatalf("creating temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	body, _ := ParseHexColor("#202124")
	outline, _ := ParseHexColor("#4c680a")

	opts := RecolorOptions{
		BodyColor:    body,
		OutlineColor: outline,
		ThemeName:    "Test-Theme",
		TargetDir:    tempDir,
	}

	if err := ExtractAndRecolor(templateBytes, opts); err != nil {
		t.Fatalf("ExtractAndRecolor failed: %v", err)
	}

	// Verify index.theme was created
	idxPath := filepath.Join(tempDir, "index.theme")
	if _, err := os.Stat(idxPath); err != nil {
		t.Errorf("index.theme missing: %v", err)
	}

	// Verify left_ptr cursor was created
	leftPtrPath := filepath.Join(tempDir, "cursors", "left_ptr")
	st, err := os.Stat(leftPtrPath)
	if err != nil {
		t.Errorf("cursors/left_ptr missing: %v", err)
	} else if st.Size() == 0 {
		t.Errorf("cursors/left_ptr is empty")
	}

	// Verify symlinks exist and point to relative targets
	defaultPath := filepath.Join(tempDir, "cursors", "default")
	link, err := os.Readlink(defaultPath)
	if err != nil {
		t.Errorf("cursors/default symlink missing: %v", err)
	} else if link != "left_ptr" {
		t.Errorf("cursors/default points to %q, expected 'left_ptr'", link)
	}
}

func BenchmarkExtractAndRecolor(b *testing.B) {
	templatePath := "../../cmd/cursor-recolor/assets/template.tar.gz"
	templateBytes, err := os.ReadFile(templatePath)
	if err != nil {
		b.Skipf("template archive not found: %v", err)
	}

	body, _ := ParseHexColor("#202124")
	outline, _ := ParseHexColor("#4c680a")

	tempDir, err := os.MkdirTemp("", "cursor-bench-*")
	if err != nil {
		b.Fatalf("creating temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	opts := RecolorOptions{
		BodyColor:    body,
		OutlineColor: outline,
		ThemeName:    "Bench-Theme",
		TargetDir:    tempDir,
	}

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = ExtractAndRecolor(templateBytes, opts)
	}
}
