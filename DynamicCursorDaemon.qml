import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

QtObject {
    id: root

    property string pluginId: ""
    property var pluginService: null

    readonly property var log: Log.scoped("DynamicCursor")

    readonly property string pluginDir: {
        const u = Qt.resolvedUrl(".").toString();
        const p = u.startsWith("file://") ? u.substring(7) : u;
        return p.endsWith("/") ? p.slice(0, -1) : p;
    }

    readonly property string helperBin: pluginDir + "/bin/cursor-recolor"

    property bool invertSets: false

    readonly property bool cursorIsDefault: {
        const cs = SettingsData.cursorSettings;
        const theme = cs && cs.theme ? cs.theme : "System Default";
        return theme === "System Default" || theme.startsWith("Dux-Dynamic-");
    }

    readonly property int cursorSize: {
        const cs = SettingsData.cursorSettings;
        return (cs && cs.size > 0) ? cs.size : 24;
    }

    readonly property string systemFallbackTheme: {
        const def = SettingsData.systemDefaultCursorTheme;
        if (def && !def.startsWith("Dux-Dynamic-")) return def;
        return "Adwaita";
    }

    property string statusMessage: "initializing"
    property string lastAppliedTheme: ""
    property string lastAppliedSlot: ""
    property int lastElapsedMs: 0
    property string lastOutline: ""
    property string lastFill: ""
    property int lastSize: 0

    function colorToHex(c) {
        if (!c) return "#ffffff";
        const r = Math.round(c.r * 255).toString(16).padStart(2, "0");
        const g = Math.round(c.g * 255).toString(16).padStart(2, "0");
        const b = Math.round(c.b * 255).toString(16).padStart(2, "0");
        return "#" + r + g + b;
    }

    readonly property string currentFillHex: {
        if (invertSets) {
            return SessionData.isLightMode ? "#202124" : "#f5f5f5";
        }
        return SessionData.isLightMode ? "#ffffff" : "#202124";
    }

    readonly property string currentOutlineHex: colorToHex(Theme.primary)

    property Timer applyTimer: Timer {
        interval: 150
        onTriggered: root.executeRecolor()
    }

    onPluginServiceChanged: reloadSettings()
    onPluginIdChanged: reloadSettings()

    property Connections pluginConnections: Connections {
        target: root.pluginService
        function onPluginDataChanged(changedId) {
            if (changedId === root.pluginId) {
                root.reloadSettings();
            }
        }
    }

    Component.onCompleted: {
        reloadSettings();
        SettingsData.cursorSettingsChanged.connect(onCursorConfigChanged);
        Theme.primaryChanged.connect(scheduleApply);
        SessionData.isLightModeChanged.connect(scheduleApply);
        Qt.callLater(startup);
    }

    Component.onDestruction: {
        applyTimer.stop();
        // When the user disables or uninstalls the plugin in DMS Settings,
        // clean up the generated cursor themes and restore the system cursor.
        // During normal shell restarts/reloads, enabled remains true and pluginDir exists.
        const stillEnabled = pluginService
            ? pluginService.loadPluginData(pluginId, "enabled", true)
            : true;
        const fallback = systemFallbackTheme;
        const sizeStr = String(cursorSize);

        const cleanupScript = 'if [ "$1" = "false" ] || [ ! -d "$2" ]; then ' +
            'rm -rf "$HOME/.local/share/icons/Dux-Dynamic-A" "$HOME/.local/share/icons/Dux-Dynamic-B" "$HOME/.cache/dms/dynamic-cursor-slot.json"; ' +
            'rm -f "$HOME/.icons/default/index.theme"; ' +
            'gsettings set org.gnome.desktop.interface cursor-theme "$3" 2>/dev/null || true; ' +
            'gsettings set org.gnome.desktop.interface cursor-size "$4" 2>/dev/null || true; ' +
            'fi';
        Quickshell.execDetached(["sh", "-c", cleanupScript, "cleanup", stillEnabled ? "true" : "false", pluginDir, fallback, sizeStr]);

        if (!stillEnabled) {
            SettingsData.updateXResources();
            SettingsData.updateCompositorCursor();
        }
    }

    function reloadSettings() {
        if (!pluginService || !pluginId) return;
        const prevInvert = invertSets;
        invertSets = pluginService.loadPluginData(pluginId, "invertSets", false);

        if (invertSets !== prevInvert) {
            scheduleApply();
        }
    }

    function startup() {
        if (cursorIsDefault) {
            scheduleApply();
        } else {
            statusMessage = "standby (custom cursor theme active)";
        }
    }

    function onCursorConfigChanged() {
        if (cursorIsDefault) {
            scheduleApply();
        } else {
            applyTimer.stop();
            statusMessage = "standby (custom cursor theme active)";
        }
    }

    function scheduleApply() {
        if (!cursorIsDefault) return;
        applyTimer.restart();
    }

    property Process recolorProc: Process {
        id: proc
        stdout: SplitParser {
            onRead: data => {
                if (!data) return;
                try {
                    const res = JSON.parse(data.trim());
                    if (res.status === "ok") {
                        root.lastAppliedTheme = res.theme || "";
                        root.lastAppliedSlot = res.slot || "";
                        root.lastElapsedMs = res.elapsed_ms || 0;
                        root.statusMessage = res.theme + " (" + res.elapsed_ms + " ms)";
                    } else if (res.status === "cleaned") {
                        root.lastAppliedTheme = "";
                        root.lastAppliedSlot = "";
                        root.lastOutline = "";
                        root.lastFill = "";
                        root.statusMessage = "cleaned (restored " + (res.theme || "default") + ")";
                        SettingsData.updateXResources();
                        SettingsData.updateCompositorCursor();
                    } else if (res.status === "error") {
                        root.statusMessage = "error: " + (res.error || "unknown");
                        root.log.error("Recolor failed: " + res.error);
                    }
                } catch (e) {
                    root.log.warning("Unexpected output: " + data);
                }
            }
        }
        stderr: SplitParser {
            onRead: err => {
                if (err && err.trim().length > 0) {
                    root.log.error("cursor-recolor: " + err.trim());
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && (root.statusMessage === "updating..." || root.statusMessage === "cleaning up...")) {
                root.statusMessage = "error (exit code " + exitCode + ")";
            }
        }
    }

    function forceRecolor() {
        lastOutline = "";
        lastFill = "";
        executeRecolor();
    }

    function cleanupThemes() {
        applyTimer.stop();
        if (proc.running) {
            proc.running = false;
        }
        statusMessage = "cleaning up...";
        const cmd = 'if [ ! -x "$1" ]; then (cd "$2" && go build -ldflags="-s -w" -o "$1" ./cmd/cursor-recolor) || exit 1; fi; exec "$1" --cleanup --fallback-theme="$3" --size="$4"';
        proc.command = ["sh", "-c", cmd, "cursor-recolor", helperBin, pluginDir, systemFallbackTheme, String(cursorSize)];
        proc.running = true;
    }

    function executeRecolor() {
        if (!cursorIsDefault) return;
        if (proc.running) {
            applyTimer.restart();
            return;
        }

        const fill = currentFillHex;
        const outline = currentOutlineHex;
        const size = cursorSize;

        if (!fill || !outline) return;
        if (outline === lastOutline && fill === lastFill && size === lastSize && lastAppliedTheme !== "") {
            return;
        }

        lastOutline = outline;
        lastFill = fill;
        lastSize = size;
        statusMessage = "updating...";

        const cmd = 'if [ ! -x "$1" ]; then (cd "$2" && go build -ldflags="-s -w" -o "$1" ./cmd/cursor-recolor) || exit 1; fi; exec "$1" --fill="$3" --outline="$4" --size="$5" --slot=auto --apply=true';
        proc.command = ["sh", "-c", cmd, "cursor-recolor", helperBin, pluginDir, fill, outline, String(size)];
        proc.running = true;
    }
}
