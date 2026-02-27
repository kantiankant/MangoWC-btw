import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

ShellRoot {

    PanelWindow {
        id: win

        // ── Corner cycling (0=BR, 1=BL, 2=TL, 3=TR) ───────────────────
        property int corner: 2

        anchors.bottom: corner === 0 || corner === 1
        anchors.top:    corner === 2 || corner === 3
        anchors.right:  corner === 0 || corner === 3
        anchors.left:   corner === 1 || corner === 2

        margins {
            bottom: (corner === 0 || corner === 1) ? 16 : 0
            top:    (corner === 2 || corner === 3) ? 16 : 0
            right:  (corner === 0 || corner === 3) ? 16 : 0
            left:   (corner === 1 || corner === 2) ? 16 : 0
        }

        property real widgetSize: 240
        readonly property real minSize: 80
        readonly property real maxSize: 240

        implicitWidth:  widgetSize
        implicitHeight: widgetSize
        color: "#00000000"

        WlrLayershell.layer:         WlrLayer.Background
        WlrLayershell.exclusiveZone: 0

        property string playbackStatus: "Stopped"
        property string trackTitle:     ""
        property string trackArtist:    ""
        property bool   isPlaying:      playbackStatus === "Playing"
        property bool isLoading: trackTitle === "" && (playbackStatus === "Playing" || playbackStatus === "Paused")

        Timer {
            id: pollTimer
            interval: 200
            repeat: true
            running: true
            onTriggered: if (!pollProcess.running) pollProcess.running = true
        }


Process {
    id: pollProcess
    command: [
        "bash", "-c",
        "playerctl metadata --format '{{status}}\n{{title}}\n{{artist}}' 2>/dev/null || printf 'Stopped\n\n'"
    ]
    running: false
    stdout: SplitParser {
        property int lineIndex: 0
        onRead: (line) => {
            var l = line.trim()
            if      (lineIndex === 0) win.playbackStatus = l || "Stopped"
            else if (lineIndex === 1) win.trackTitle     = l
            else if (lineIndex === 2) win.trackArtist    = l
            lineIndex = (lineIndex + 1) % 3
        }
    }
}

        function runPlayerctl(args) {
            playerctlRunner.command = ["playerctl"].concat(args)
            playerctlRunner.running = false
            playerctlRunner.running = true
            pollTimer.restart()
        }

        Process {
            id: playerctlRunner
            command: ["playerctl", "status"]
            running: false
        }

        // ── Card ───────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            radius: win.widgetSize * 0.20
            color:  "#ffffff"

            Rectangle {
                anchors { top: parent.top; topMargin: 1; horizontalCenter: parent.horizontalCenter }
                width: parent.width * 0.5; height: 1; radius: 1
                color: Qt.rgba(0, 0, 0, 0.08)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton)
                        win.corner = (win.corner + 1) % 4
                }

                property real dragStartX:    0
                property real dragStartY:    0
                property real dragStartSize: 0

                onPressed: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        dragStartX    = mouse.x
                        dragStartY    = mouse.y
                        dragStartSize = win.widgetSize
                    }
                }

                onPositionChanged: (mouse) => {
                    if (pressedButtons & Qt.RightButton) {
                        var dx      = mouse.x - dragStartX
                        var dy      = mouse.y - dragStartY
                        var delta   = (dx + dy) / 2
                        var newSize = dragStartSize + delta
                        win.widgetSize = Math.max(win.minSize, Math.min(win.maxSize, newSize))
                    }
                }
            }

            // ── Track title — scrolls if too long, centres if it fits ──
            Item {
                id: titleMarquee
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: win.widgetSize * 0.18
                }
                width:  win.widgetSize * 0.78
                height: win.widgetSize * 0.12
                clip:   true

                Text {
                    id: titleText
                    text: win.trackTitle || "Nothing"
                    font.family:    "SF Pro Display"
                    font.pixelSize: win.widgetSize * 0.095
                    font.weight:    Font.Medium
                    color: Qt.rgba(0, 0, 0, 0.80)

                    x: titleText.width <= titleMarquee.width
                       ? (titleMarquee.width - titleText.width) / 2
                       : titleText.x

                    SequentialAnimation on x {
                        running:  titleText.width > titleMarquee.width
                        loops:    Animation.Infinite
                        PauseAnimation  { duration: 1800 }
                        NumberAnimation {
                            to:       -(titleText.width - titleMarquee.width + win.widgetSize * 0.05)
                            duration: Math.max(2000, (titleText.width - titleMarquee.width) * 12)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation  { duration: 1200 }
                        NumberAnimation { to: 0; duration: 0 }
                    }
                }
            }

            // ── Artist name ────────────────────────────────────────────
            Item {
                id: artistMarquee
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: win.widgetSize * 0.18 + win.widgetSize * 0.115
                }
                width:  win.widgetSize * 0.78
                height: win.widgetSize * 0.11
                clip:   true

                Text {
                    id: artistText
                    text: win.trackArtist || "Nobody"
                    font.family:    "SF Pro Display"
                    font.pixelSize: win.widgetSize * 0.080
                    color: Qt.rgba(0, 0, 0, 0.45)

                    x: artistText.width <= artistMarquee.width
                       ? (artistMarquee.width - artistText.width) / 2
                       : artistText.x

                    SequentialAnimation on x {
                        running:  artistText.width > artistMarquee.width
                        loops:    Animation.Infinite
                        PauseAnimation  { duration: 1800 }
                        NumberAnimation {
                            to:       -(artistText.width - artistMarquee.width + win.widgetSize * 0.05)
                            duration: Math.max(2000, (artistText.width - artistMarquee.width) * 12)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation  { duration: 1200 }
                        NumberAnimation { to: 0; duration: 0 }
                    }
                }
            }

            // ── Controls row ───────────────────────────────────────────
            Row {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: win.widgetSize * 0.18
                }
                spacing: win.widgetSize * 0.08

                Text {
                    text: "\uf048"
                    font.family:    "Symbols Nerd Font"
                    font.pixelSize: win.widgetSize * 0.18
                    color: Qt.rgba(0, 0, 0, 0.55)
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: false
                        onClicked:  win.runPlayerctl(["previous"])
                        onPressed:  parent.color = Qt.rgba(0, 0, 0, 0.85)
                        onReleased: parent.color = Qt.rgba(0, 0, 0, 0.55)
                    }
                }

                Item {
                    width:  win.widgetSize * 0.30
                    height: win.widgetSize * 0.30
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        id: playButton
                        anchors.centerIn: parent
                        text: win.isPlaying ? "\uf28b" : "\uf144"
                        font.family:    "Symbols Nerd Font"
                        font.pixelSize: win.widgetSize * 0.26
                        color: Qt.rgba(0, 0, 0, 0.80)
                        Behavior on color { ColorAnimation { duration: 150 } }

                        property real bounceScale: 1.0
                        transform: Scale {
                            origin.x: playButton.width  / 2
                            origin.y: playButton.height / 2
                            xScale: playButton.bounceScale
                            yScale: playButton.bounceScale
                        }

                        SequentialAnimation {
                            running: win.isLoading
                            loops:   Animation.Infinite
                            NumberAnimation {
                                target:   playButton
                                property: "bounceScale"
                                to:       1.40
                                duration: 380
                                easing.type:      Easing.OutBack
                                easing.overshoot: 4.5
                            }
                            NumberAnimation {
                                target:   playButton
                                property: "bounceScale"
                                to:       1.0
                                duration: 380
                                easing.type:      Easing.InBack
                                easing.overshoot: 3.0
                            }
                            PauseAnimation { duration: 150 }
                        }

                        SequentialAnimation {
                            running: win.isLoading
                            loops:   Animation.Infinite
                            NumberAnimation {
                                target:   playButton
                                property: "opacity"
                                to:       0.08
                                duration: 300
                                easing.type: Easing.InOutSine
                            }
                            PauseAnimation { duration: 60 }
                            NumberAnimation {
                                target:   playButton
                                property: "opacity"
                                to:       1.0
                                duration: 300
                                easing.type: Easing.InOutSine
                            }
                        }

                        onVisibleChanged: {
                            if (!win.isLoading) {
                                bounceScale = 1.0
                                opacity     = 1.0
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: false
                        onClicked:  win.runPlayerctl(["play-pause"])
                        onPressed:  playButton.color = Qt.rgba(0, 0, 0, 0.95)
                        onReleased: playButton.color = Qt.rgba(0, 0, 0, 0.80)
                    }
                }

                Text {
                    text: "\uf051"
                    font.family:    "Symbols Nerd Font"
                    font.pixelSize: win.widgetSize * 0.18
                    color: Qt.rgba(0, 0, 0, 0.55)
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: false
                        onClicked:  win.runPlayerctl(["next"])
                        onPressed:  parent.color = Qt.rgba(0, 0, 0, 0.85)
                        onReleased: parent.color = Qt.rgba(0, 0, 0, 0.55)
                    }
                }
            }

            // ── Nothing playing indicator ──────────────────────────────
            Rectangle {
                visible: win.playbackStatus === "Stopped"
                anchors {
                    bottom: parent.bottom
                    bottomMargin: win.widgetSize * 0.07
                    horizontalCenter: parent.horizontalCenter
                }
                width: win.widgetSize * 0.25; height: 2; radius: 1
                color: Qt.rgba(0, 0, 0, 0.15)
            }
        }
    }
}
