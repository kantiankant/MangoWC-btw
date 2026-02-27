import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    PanelWindow {
        id: win

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        color: "#000000"

        readonly property int    charH:    18
        readonly property int    charW:    9
        readonly property color  cGreen:   "#AAAAAA"
        readonly property color  cHiText:  "#000000"
        readonly property color  cHiBg:    "#AAAAAA"
        readonly property string monoFont: "monospace"

        property int selectedIndex: 0
        readonly property var entries: [
            { label: "Power Off", cmd: ["poweroff"] },
            { label: "Reboot",    cmd: ["reboot"] },
            { label: "Sleep",     cmd: ["systemctl", "suspend"] },
            { label: "Lock",      cmd: ["hyprlock"] },
            { label: "Log Out",   cmd: ["pkill", "mango"] }
        ]

        Process {
            id: proc
            running: false
            command: []
            onExited: Qt.quit()
        }

        function execute(index) {
            proc.command = entries[index].cmd
            proc.running = true
        }

        Item {
            anchors.fill: parent
            focus: true

            Keys.onPressed: function(ev) {
                if (ev.key === Qt.Key_Up || ev.key === Qt.Key_K) {
                    win.selectedIndex = (win.selectedIndex - 1 + win.entries.length) % win.entries.length
                    ev.accepted = true
                } else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_J) {
                    win.selectedIndex = (win.selectedIndex + 1) % win.entries.length
                    ev.accepted = true
                } else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
                    win.execute(win.selectedIndex)
                    ev.accepted = true
                } else if (ev.key === Qt.Key_Escape) {
                    Qt.quit()
                    ev.accepted = true
                }
            }

            Text {
                x: win.charW * 2
                y: win.charH
                text: "GNU GRUB  version 2.14-1"
                color: win.cGreen
                font.family: win.monoFont
                font.pixelSize: win.charH
            }

            readonly property int boxCols: 44
            readonly property int boxRows: win.entries.length + 4
            readonly property int boxX: Math.floor((width  - boxCols * win.charW) / 2)
            readonly property int boxY: Math.floor((height - boxRows * win.charH) / 2)

            Rectangle {
                x: parent.boxX
                y: parent.boxY
                width:  parent.boxCols * win.charW
                height: parent.boxRows * win.charH
                color:  "transparent"
                border.color: win.cGreen
                border.width: 1

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    color: "transparent"
                    border.color: win.cGreen
                    border.width: 1
                }
            }

            Column {
                x: parent.boxX + win.charW * 2
                y: parent.boxY + win.charH * 2
                spacing: 0

                Repeater {
                    model: win.entries.length
                    delegate: Item {
                        required property int index
                        width:  (parent.parent.boxCols - 4) * win.charW
                        height: win.charH

                        Rectangle {
                            anchors.fill: parent
                            color: index === win.selectedIndex ? win.cHiBg : "transparent"
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: win.charW
                            text: win.entries[index].label
                            color: index === win.selectedIndex ? win.cHiText : win.cGreen
                            font.family: win.monoFont
                            font.pixelSize: win.charH
                        }
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: win.charH * 2
                x: win.charW * 2
                text: "Use the \u2191 and \u2193 keys to select which entry is highlighted.\nPress enter to accept, Escape to cancel."
                color: win.cGreen
                font.family: win.monoFont
                font.pixelSize: win.charH
                lineHeightMode: Text.FixedHeight
                lineHeight: win.charH * 1.4
            }
        }
    }
}
