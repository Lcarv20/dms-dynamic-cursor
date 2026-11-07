package xcursor

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"encoding/binary"
	"fmt"
	"image/color"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const (
	XcursorMagic = 0x72756358 // "Xcur" in little-endian uint32
	ChunkImage   = 0xFFFD0002
)

type RecolorOptions struct {
	BodyColor    color.RGBA
	OutlineColor color.RGBA
	ThemeName    string
	TargetDir    string
}

func ParseHexColor(s string) (color.RGBA, error) {
	s = strings.TrimPrefix(s, "#")
	if len(s) != 6 {
		return color.RGBA{}, fmt.Errorf("invalid hex color %q (expected RRGGBB)", s)
	}
	var r, g, b uint8
	if _, err := fmt.Sscanf(s, "%02x%02x%02x", &r, &g, &b); err != nil {
		return color.RGBA{}, fmt.Errorf("parsing hex color %q: %w", s, err)
	}
	return color.RGBA{R: r, G: g, B: b, A: 255}, nil
}

func IsXcursor(data []byte) bool {
	return len(data) >= 16 && binary.LittleEndian.Uint32(data[0:4]) == XcursorMagic
}

// RecolorBuffer recolors all image chunks in an Xcursor binary in place.
// The template uses premultiplied grayscale where luminance maps linearly
// between the body fill color (0) and the outline color (255).
func RecolorBuffer(data []byte, body, outline color.RGBA) error {
	if len(data) < 16 {
		return fmt.Errorf("buffer too short for Xcursor header")
	}

	magic := binary.LittleEndian.Uint32(data[0:4])
	if magic != XcursorMagic {
		return fmt.Errorf("invalid Xcursor magic: 0x%08x", magic)
	}

	ntoc := binary.LittleEndian.Uint32(data[12:16])
	if len(data) < int(16+12*ntoc) {
		return fmt.Errorf("truncated Xcursor TOC")
	}

	bodyR, bodyG, bodyB := int(body.R), int(body.G), int(body.B)
	outR, outG, outB := int(outline.R), int(outline.G), int(outline.B)

	for i := uint32(0); i < ntoc; i++ {
		tocOff := 16 + 12*i
		chunkType := binary.LittleEndian.Uint32(data[tocOff : tocOff+4])
		pos := int(binary.LittleEndian.Uint32(data[tocOff+8 : tocOff+12]))

		if chunkType != ChunkImage || pos+36 > len(data) {
			continue
		}

		w := int(binary.LittleEndian.Uint32(data[pos+16 : pos+20]))
		h := int(binary.LittleEndian.Uint32(data[pos+20 : pos+24]))
		pixelsEnd := pos + 36 + w*h*4
		if pixelsEnd > len(data) {
			continue
		}

		pixels := data[pos+36 : pixelsEnd]
		for p := 0; p < len(pixels); p += 4 {
			// ARGB32 little-endian: B, G, R, A
			a := int(pixels[p+3])
			if a == 0 {
				pixels[p] = 0
				pixels[p+1] = 0
				pixels[p+2] = 0
				continue
			}

			lum := (int(pixels[p+2]) * 256) / a
			if lum > 256 {
				lum = 256
			}
			inv := 256 - lum

			r := (bodyR*inv + outR*lum) / 256
			g := (bodyG*inv + outG*lum) / 256
			b := (bodyB*inv + outB*lum) / 256

			pixels[p] = uint8((b * a) / 255)
			pixels[p+1] = uint8((g * a) / 255)
			pixels[p+2] = uint8((r * a) / 255)
		}
	}

	return nil
}

func ExtractAndRecolor(templateGz []byte, opts RecolorOptions) error {
	gzr, err := gzip.NewReader(bytes.NewReader(templateGz))
	if err != nil {
		return fmt.Errorf("opening gzip reader: %w", err)
	}
	defer gzr.Close()

	cleanTarget := filepath.Clean(opts.TargetDir)
	if err := os.MkdirAll(cleanTarget, 0755); err != nil {
		return fmt.Errorf("creating target dir: %w", err)
	}

	tr := tar.NewReader(gzr)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("reading tar entry: %w", err)
		}

		targetPath := filepath.Join(cleanTarget, header.Name)
		if !strings.HasPrefix(targetPath, cleanTarget+string(os.PathSeparator)) && targetPath != cleanTarget {
			return fmt.Errorf("invalid tar path: %s", header.Name)
		}

		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(targetPath, 0755); err != nil {
				return fmt.Errorf("creating dir %s: %w", targetPath, err)
			}

		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
				return err
			}
			_ = os.Remove(targetPath)
			if err := os.Symlink(header.Linkname, targetPath); err != nil {
				return fmt.Errorf("creating symlink %s -> %s: %w", targetPath, header.Linkname, err)
			}

		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
				return err
			}

			buf := make([]byte, header.Size)
			if _, err := io.ReadFull(tr, buf); err != nil {
				return fmt.Errorf("reading %s: %w", header.Name, err)
			}

			if filepath.Base(header.Name) == "index.theme" {
				themeContent := fmt.Sprintf("[Icon Theme]\nName=%s\nComment=Dynamic Material Cursor\nInherits=Adwaita\n", opts.ThemeName)
				if err := os.WriteFile(targetPath, []byte(themeContent), 0644); err != nil {
					return fmt.Errorf("writing index.theme: %w", err)
				}
				continue
			}

			if filepath.Base(filepath.Dir(targetPath)) == "cursors" && IsXcursor(buf) {
				if err := RecolorBuffer(buf, opts.BodyColor, opts.OutlineColor); err != nil {
					return fmt.Errorf("recoloring %s: %w", header.Name, err)
				}
			}

			if err := os.WriteFile(targetPath, buf, 0644); err != nil {
				return fmt.Errorf("writing %s: %w", targetPath, err)
			}
		}
	}

	return nil
}
