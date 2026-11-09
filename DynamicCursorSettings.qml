import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dmsDynamicCursor"

    function daemon() {
        return pluginService && pluginService.pluginDaemonInstances
            ? (pluginService.pluginDaemonInstances["dmsDynamicCursor"] || null)
            : null;
    }

    StyledText {
        text: "Dynamic Palette Cursor"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent ? parent.width : 360
        wrapMode: Text.Wrap
        text: "Dynamically recolors mouse cursors in real time to match the DMS Material 3 wallpaper palette. Generates exact color matches with sub-50ms latency using a standalone native Go engine."
        color: Theme.surfaceTextSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

    // ------------------------------------------------------------ Status Card
    Rectangle {
        width: parent ? parent.width : 360
        height: statusCol.implicitHeight + 24
        radius: Theme.borderRadiusMedium
        color: Theme.withAlpha(Theme.surfaceVariant, 0.4)
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.5)
        border.width: 1

        Column {
            id: statusCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 8

            Row {
                spacing: 8
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    anchors.verticalCenter: parent.verticalCenter
                    color: {
                        const d = root.daemon();
                        return (d && d.currentOutlineHex) ? d.currentOutlineHex : Theme.primary;
                    }
                    border.color: Theme.withAlpha(Theme.surfaceText, 0.3)
                    border.width: 1
                }

                StyledText {
                    text: {
                        const d = root.daemon();
                        if (!d) return "Daemon status: Not running";
                        return "Status: " + d.statusMessage;
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }
            }

            StyledText {
                text: {
                    const d = root.daemon();
                    if (!d) return "";
                    const theme = d.lastAppliedTheme || "Dux-Dynamic";
                    const slot = d.lastAppliedSlot || "—";
                    const ms = d.lastElapsedMs || 0;
                    return "Active Theme: " + theme + " (Slot: " + slot + ") · Latency: " + ms + " ms";
                }
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    // ------------------------------------------------------------ Actions
    Row {
        spacing: Theme.spacingM

        DButton {
            text: "Recolor Now"
            iconName: "refresh"
            onClicked: {
                const d = root.daemon();
                if (d) {
                    d.lastAccent = ""; // force re-evaluation
                    d.executeRecolor();
                }
            }
        }
    }

    // ------------------------------------------------------------ Settings
    ToggleSetting {
        settingKey: "enabled"
        label: "Enable dynamic palette cursor"
        description: "Master switch. Automatically follows desktop wallpaper palette changes."
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "invertSets"
        label: "Invert cursor contrast"
        description: "Use dark cursor body in light mode and light cursor body in dark mode."
        defaultValue: false
    }

    onSettingChanged: {
        const d = root.daemon();
        if (d) {
            d.reloadSettings();
        }
    }
}
