import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    anchors.bottom: true
    anchors.left: true
    margins.bottom: 25
    margins.left: 20

    implicitWidth: 240
    implicitHeight: 240
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "clock"

    // Background
    Rectangle {
        anchors.fill: parent
        radius: 36
        color: "#272729"
    }
    Rectangle {
        anchors.fill: parent
        radius: 36
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.18)
        border.width: 1
    }

    // Clock face — everything relative to cx/cy/r so scaling just works
    Item {
        id: face
        anchors.fill: parent
        layer.enabled: true
        z: 1

        property real cx: width / 2
        property real cy: height / 2
        property real r: Math.min(width, height) * 0.46

        // White circle
        Rectangle {
            width: face.r * 2; height: face.r * 2
            radius: face.r
            color: "white"
            x: face.cx - face.r; y: face.cy - face.r
        }

        // Inner shadow rings
        Rectangle {
            width: face.r * 2; height: face.r * 2; radius: face.r
            x: face.cx - face.r; y: face.cy - face.r
            color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.09)
            border.width: 5
        }
        Rectangle {
            width: face.r * 1.91; height: face.r * 1.91; radius: face.r
            x: face.cx - face.r * 0.955; y: face.cy - face.r * 0.955
            color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.04)
            border.width: 3
        }

        // Tick marks
        Repeater {
            model: 60
            delegate: Rectangle {
                id: tick
                property bool isMajor: index % 5 === 0
                width: isMajor ? 2.5 : 1
                height: isMajor ? face.r * 0.14 : face.r * 0.07
                color: isMajor ? "#333333" : "#aaaaaa"
                antialiasing: true
                x: face.cx - width / 2
                y: face.cy - face.r * 0.97
                transform: Rotation {
                    origin.x: tick.width / 2
                    origin.y: face.cy - (face.cy - face.r * 0.97)
                    angle: index * 6
                }
            }
        }

        // Hour numbers
        Repeater {
            model: 12
            delegate: Text {
                property real angle: (index + 1) * 30 * Math.PI / 180
                property real nr: face.r * 0.72
                x: face.cx + nr * Math.sin(angle) - width / 2
                y: face.cy - nr * Math.cos(angle) - height / 2
                text: index + 1
                font.pixelSize: face.r * 0.16
                font.weight: Font.Medium
                color: "#111111"
            }
        }

        // Hour hand
        Rectangle {
            id: hourHand
            width: 5; height: face.r * 0.52; radius: 2.5
            color: "#1a1a1a"; antialiasing: true
            x: face.cx - width / 2; y: face.cy - height
            transform: Rotation {
                origin.x: hourHand.width / 2; origin.y: hourHand.height
                angle: (clock.hours % 12) * 30 + clock.minutes * 0.5
            }
        }

        // Minute hand
        Rectangle {
            id: minuteHand
            width: 3.5; height: face.r * 0.82; radius: 2
            color: "#1a1a1a"; antialiasing: true
            x: face.cx - width / 2; y: face.cy - height
            transform: Rotation {
                origin.x: minuteHand.width / 2; origin.y: minuteHand.height
                angle: clock.minutes * 6 + clock.seconds * 0.1
            }
        }

        // Second hand
        Rectangle {
            id: secondHand
            width: 1.5; height: face.r * 0.90; radius: 1
            color: "#DAB275"; antialiasing: true
            x: face.cx - width / 2; y: face.cy - height
            transform: Rotation {
                origin.x: secondHand.width / 2; origin.y: secondHand.height
                angle: clock.seconds * 6
            }
        }

        // Second tail
        Rectangle {
            id: secondTail
            width: 1.5; height: face.r * 0.23; radius: 1
            color: "#DAB275"; antialiasing: true
            x: face.cx - width / 2; y: face.cy
            transform: Rotation {
                origin.x: secondTail.width / 2; origin.y: 0
                angle: clock.seconds * 6 + 180
            }
        }

        // Centre pip
        Rectangle {
            width: 10; height: 10; radius: 5
            color: "#DAB275"
            x: face.cx - 5; y: face.cy - 5
            z: 10
        }
    }

    QtObject {
        id: clock
        property int hours: 0
        property int minutes: 0
        property int seconds: 0
        function update() {
            var now = new Date()
            hours = now.getHours()
            minutes = now.getMinutes()
            seconds = now.getSeconds()
        }
        Component.onCompleted: update()
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: clock.update()
    }
}
