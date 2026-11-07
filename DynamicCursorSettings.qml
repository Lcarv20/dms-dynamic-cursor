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
        wrapMode: Text.WordWrap
        text: "Recolors the cursor theme to match the active DMS Material 3 primary accent."
        color: Theme.surfaceTextSecondary
        font.pixelSize: Theme.fontSizeSmall
    }

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
                        if (!d) return "Daemon not running";
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
                    if (!d || !d.lastAppliedTheme) return "Theme: not yet applied";
                    return "Theme: " + d.lastAppliedTheme + " (slot " + d.lastAppliedSlot + ")";
                }
                color: Theme.surfaceTextSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    Row {
        spacing: Theme.spacingM

        DButton {
            text: "Recolor Now"
            iconName: "refresh"
            onClicked: {
                const d = root.daemon();
                if (d) d.forceRecolor();
            }
        }

        DButton {
            text: "Reset & Clean Up"
            iconName: "delete_sweep"
            onClicked: {
                const d = root.daemon();
                if (d) d.cleanupThemes();
            }
        }
    }

    ToggleSetting {
        settingKey: "invertSets"
        label: "Invert cursor contrast"
        description: "Use a dark cursor fill in light mode and a light fill in dark mode."
        defaultValue: false
    }
}
