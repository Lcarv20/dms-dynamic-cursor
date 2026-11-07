# Dynamic Palette Cursor (`dms-dynamic-cursor`)

A cursor plugin for [Dux Modular Shell](https://github.com/duxlabs-dev/dux-shell) (DMS) that recolors your mouse cursor in real time to match your wallpaper's Material 3 palette. Whenever your wallpaper accent or light/dark mode changes, the cursor body and outline update automatically to follow `Theme.primary`.

<p align="center">
  <img src="docs/cursor-default.png" width="170" alt="Default cursor" />
  <img src="docs/cursor-pointer.png" width="170" alt="Pointer cursor" />
  <img src="docs/cursor-text.png" width="170" alt="Text cursor" />
</p>

<p align="center"><em>Cursor shapes from the template, recolored with different Material 3 palette accents.</em></p>

## Installation

1. Clone the repository into your DMS plugins directory and build the helper binary:

```bash
git clone https://github.com/Lcarv20/dms-dynamic-cursor.git ~/.config/dms/plugins/dms-dynamic-cursor
cd ~/.config/dms/plugins/dms-dynamic-cursor
make
```

2. Enable **Dynamic Palette Cursor** in DMS Settings → Plugins, and leave your DMS cursor theme set to **System Default** (selecting a different theme in DMS Settings will put the plugin on standby).

> Note: If `bin/cursor-recolor` hasn't been built yet when the plugin starts, the daemon will compile it automatically on first run as long as `go` is installed.

## Credits

The cursor set is based on [material-bibata-cursor](https://github.com/SakibShahariar/material-bibata-cursor) by [Sakib Shahariar](https://github.com/SakibShahariar).
