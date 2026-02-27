// Wallpaper switcher — swww backend
// Run with: quickshell -p wallpaper.qml

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property string sf:  "SF Pro Display"
    readonly property string sfi: "SF Symbols"

    // ── State ──────────────────────────────────────────────────
    property var    wallpapers:    []
    property int    selectedIndex: -1
    property string searchText:    ""
    property string ghostSuffix:   ""
    property string currentWall:   ""
    property bool   applying:      false

    // swww transition pool — random one picked each apply
    readonly property var transitions: [
        "fade", "wave", "wipe", "grow", "outer",
        "center", "any", "random"
    ]

    // ── Scan ~/.config/mango/walls for images ──────────────────
    Process {
        id: wallScanProc
        command: [
            "bash", "-c",
            "find ~/.config/mango/walls -maxdepth 2 " +
            "  \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "     -o -iname '*.webp' -o -iname '*.gif' \\) " +
            "  2>/dev/null | sort"
        ]
        running: true
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim()
                if (p.length === 0) return
                var list = shell.wallpapers.slice()
                list.push(p)
                shell.wallpapers = list
            }
        }
    }

    // ── Get current wallpaper from swww ────────────────────────
    Process {
        id: currentWallProc
        command: ["bash", "-c", "swww query 2>/dev/null | grep -oP 'image: \\K.*' | head -1"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                var p = line.trim()
                if (p.length > 0) shell.currentWall = p
            }
        }
    }

    // ── Apply wallpaper ────────────────────────────────────────
    Process {
        id: applyProc
        running: false
        onRunningChanged: {
            // Wait for swww to actually finish, THEN close
            if (!running) {
                shell.applying = false
                Qt.quit()
            }
        }
    }

    function applyWallpaper(path) {
        if (shell.applying) return
        shell.applying    = true
        shell.currentWall = path

        // Pick a random transition
        var t   = shell.transitions[Math.floor(Math.random() * shell.transitions.length)]
        var dur = (0.8 + Math.random() * 1.2).toFixed(1)
        var fps = Math.floor(30 + Math.random() * 30)

        applyProc.command = [
            "bash", "-c",
            "swww img '" + path.replace(/'/g, "'\\''") + "' " +
            "  --transition-type "     + t   + " " +
            "  --transition-duration " + dur + " " +
            "  --transition-fps "      + fps + " " +
            "  --transition-bezier '.43,1.0,.41,1.0' " +
            "2>/dev/null"
        ]
        applyProc.running = true
        // NO Qt.quit() here — we wait for onRunningChanged above
    }

    // ── Filter / search logic (mirrors launcher) ───────────────
    ListModel { id: filteredModel }

    function basename(path) {
        return path.split("/").pop().replace(/\.[^.]+$/, "")
    }

    function filterWalls(q) {
        filteredModel.clear()
        shell.selectedIndex = -1
        shell.ghostSuffix   = ""
        shell.searchText    = q

        var list = q === "" ? shell.wallpapers : shell.wallpapers.filter(function(p) {
            return basename(p).toLowerCase().includes(q.toLowerCase())
        })

        for (var i = 0; i < list.length && filteredModel.count < 200; i++)
            filteredModel.append({ wallPath: list[i], wallName: basename(list[i]) })

        if (filteredModel.count > 0 && q !== "") {
            var first = filteredModel.get(0).wallName
            shell.ghostSuffix = first.toLowerCase().startsWith(q.toLowerCase())
                ? first.substring(q.length) : ""
        }
    }

    // Rebuild filtered list whenever wallpapers list changes
    onWallpapersChanged: filterWalls(shell.searchText)

    function selectUp() {
        if (filteredModel.count === 0) return
        shell.selectedIndex = shell.selectedIndex <= 0
            ? filteredModel.count - 1 : shell.selectedIndex - 1
        updateGhost()
    }

    function selectDown() {
        if (filteredModel.count === 0) return
        shell.selectedIndex = shell.selectedIndex >= filteredModel.count - 1
            ? 0 : shell.selectedIndex + 1
        updateGhost()
    }

    function updateGhost() {
        if (shell.selectedIndex < 0 || shell.selectedIndex >= filteredModel.count) return
        var name = filteredModel.get(shell.selectedIndex).wallName
        shell.ghostSuffix = name.toLowerCase().startsWith(shell.searchText.toLowerCase())
            ? name.substring(shell.searchText.length) : ""
    }

    function confirmSelection() {
        if (shell.selectedIndex >= 0 && shell.selectedIndex < filteredModel.count)
            applyWallpaper(filteredModel.get(shell.selectedIndex).wallPath)
        else if (filteredModel.count > 0)
            applyWallpaper(filteredModel.get(0).wallPath)
        else
            Qt.quit()
    }

    // ── UI ─────────────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            property var modelData
            screen: modelData

            WlrLayershell.layer:         WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace:     "wallpaper-switcher"

            anchors.top:    true
            anchors.bottom: true
            anchors.left:   true
            anchors.right:  true
            color:          "transparent"
            exclusiveZone:  0

            // Geometry — centred pill, same proportions as launcher
            readonly property real barCY:      height * 0.5 - height * 0.12
            readonly property real pillW:      480
            readonly property real pillH:      56
            readonly property real pillX:      width  * 0.5 - pillW * 0.5
            readonly property real pillY:      barCY  - pillH * 0.5
            readonly property int  maxVisible: 8
            readonly property int  itemH:      44

            readonly property real dropTargetH: filteredModel.count > 0
                ? Math.min(filteredModel.count, win.maxVisible) * win.itemH + 12
                : 0

            Component.onCompleted: {
                entranceAnim.start()
                searchInput.forceActiveFocus()
                // populate immediately with all walls
                shell.filterWalls("")
            }

            // Click outside → dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    if (mouseX >= win.pillX && mouseX <= win.pillX + win.pillW &&
                        mouseY >= win.pillY && mouseY <= win.pillY + win.pillH + dropdown.height)
                        { mouse.accepted = false; return }
                    Qt.quit()
                }
            }

            // ── Search pill ────────────────────────────────────
            Rectangle {
                id: searchPill
                x:      win.pillX
                y:      win.pillY
                width:  win.pillW
                height: win.pillH

                readonly property bool dropOpen: dropdown.height > 1
                topLeftRadius:     win.pillH * 0.5
                topRightRadius:    win.pillH * 0.5
                bottomLeftRadius:  dropOpen ? 0 : win.pillH * 0.5
                bottomRightRadius: dropOpen ? 0 : win.pillH * 0.5
                Behavior on bottomLeftRadius  { NumberAnimation { duration: 120 } }
                Behavior on bottomRightRadius { NumberAnimation { duration: 120 } }

                color:        Qt.rgba(0,0,0,0.12)
                border.color: Qt.rgba(1,1,1,0.12)
                border.width: 1
                opacity: 0

                Row {
                    anchors.left:           parent.left
                    anchors.leftMargin:     18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // Wallpaper icon
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "􀏛"   // SF Symbol: photo
                        font.family: shell.sfi; font.pixelSize: 17
                        font.weight: Font.Medium; color: Qt.rgba(1,1,1,0.45)
                    }

                    Item {
                        width:  win.pillW - 18 - 24 - 8 - 18
                        height: win.pillH
                        anchors.verticalCenter: parent.verticalCenter

                        // Ghost autocomplete text
                        Text {
                            id: ghostMeasure
                            anchors.verticalCenter: parent.verticalCenter
                            text:    shell.searchText
                            font.pixelSize: 16; font.family: shell.sf; font.weight: Font.Medium
                            color:   "transparent"
                            visible: shell.ghostSuffix !== ""
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:           ghostMeasure.right
                            visible:  shell.ghostSuffix !== "" && shell.searchText !== ""
                            text:     shell.ghostSuffix
                            font.pixelSize: 16; font.family: shell.sf; font.weight: Font.Medium
                            color:    Qt.rgba(1,1,1,0.25)
                        }

                        TextField {
                            id: searchInput
                            anchors.fill:         parent
                            background:           null
                            color:                Qt.rgba(1,1,1,0.92)
                            placeholderText:      "Search wallpapers…"
                            placeholderTextColor: Qt.rgba(1,1,1,0.30)
                            font.pixelSize: 16; font.family: shell.sf; font.weight: Font.Medium
                            leftPadding: 0; rightPadding: 0
                            verticalAlignment: TextInput.AlignVCenter

                            onTextChanged:      shell.filterWalls(text.trim())
                            Keys.onUpPressed:   shell.selectUp()
                            Keys.onDownPressed: shell.selectDown()
                            Keys.onTabPressed: {
                                if (filteredModel.count > 0) {
                                    var idx  = shell.selectedIndex >= 0 ? shell.selectedIndex : 0
                                    var name = filteredModel.get(idx).wallName
                                    searchInput.text = name
                                    searchInput.cursorPosition = name.length
                                    shell.selectedIndex = idx
                                    shell.ghostSuffix   = ""
                                }
                            }
                            Keys.onReturnPressed: shell.confirmSelection()
                            Keys.onEscapePressed: Qt.quit()
                        }
                    }
                }

                // Applying spinner / count badge on the right
                Row {
                    anchors.right:          parent.right
                    anchors.rightMargin:    18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        visible: shell.applying
                        text:    "􀍠"   // SF Symbol: arrow.triangle.2.circlepath
                        font.family: shell.sfi; font.pixelSize: 15
                        color: Qt.rgba(1,1,1,0.55)
                        RotationAnimator on rotation {
                            running: shell.applying
                            from: 0; to: 360; duration: 800
                            loops: Animation.Infinite
                        }
                    }

                    Rectangle {
                        visible: !shell.applying && shell.wallpapers.length > 0
                        height: 18
                        width:  countLabel.implicitWidth + 12
                        radius: 9
                        color:  Qt.rgba(1,1,1,0.07)
                        border.color: Qt.rgba(1,1,1,0.10); border.width: 1
                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: shell.wallpapers.length + " walls"
                            font.family: shell.sf; font.pixelSize: 10
                            color: Qt.rgba(1,1,1,0.35)
                        }
                    }

                    Text {
                        visible: !shell.applying && shell.wallpapers.length === 0
                        text: "No walls found"
                        font.family: shell.sf; font.pixelSize: 11
                        color: Qt.rgba(1,1,1,0.25)
                    }
                }
            }

            // ── Dropdown ───────────────────────────────────────
            Rectangle {
                id: dropdown
                x:      win.pillX
                y:      win.pillY + win.pillH
                width:  win.pillW

                topLeftRadius:     0
                topRightRadius:    0
                bottomLeftRadius:  30
                bottomRightRadius: 30

                height: 0
                Behavior on height {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.2, 0.8, 0.2, 1.0, 1.0, 1.0]
                    }
                }
                Component.onCompleted: height = Qt.binding(() => win.dropTargetH)

                color:        Qt.rgba(0,0,0,0.12)
                border.color: Qt.rgba(1,1,1,0.10)
                border.width: 1
                clip:         true
                opacity:      searchPill.opacity
                visible:      height > 0 || win.dropTargetH > 0

                ListView {
                    id: resultsView
                    anchors.fill:         parent
                    anchors.topMargin:    6
                    anchors.bottomMargin: 6
                    model:          filteredModel
                    clip:           true
                    interactive:    filteredModel.count > win.maxVisible
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: filteredModel.count > win.maxVisible
                                ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
                        contentItem: Rectangle {
                            implicitWidth: 4; implicitHeight: 40
                            radius: 2; color: Qt.rgba(1,1,1,0.12)
                        }
                    }

                    delegate: Item {
                        required property int    index
                        required property string wallPath
                        required property string wallName

                        width:  resultsView.width
                        height: win.itemH

                        property bool isSelected:  index === shell.selectedIndex
                        property bool isCurrent:   wallPath === shell.currentWall

                        // Hover / selected background
                        Rectangle {
                            anchors.fill:        parent
                            anchors.leftMargin:  4
                            anchors.rightMargin: 4
                            radius: 10
                            color: isSelected    ? Qt.rgba(1,1,1,0.14)
                                 : rowHover.hovered ? Qt.rgba(1,1,1,0.07)
                                 : "transparent"
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }

                        // Divider
                        Rectangle {
                            anchors.bottom:      parent.bottom
                            anchors.left:        parent.left;  anchors.leftMargin:  16
                            anchors.right:       parent.right; anchors.rightMargin: 16
                            height:  1
                            color:   Qt.rgba(1,1,1,0.07)
                            visible: index < filteredModel.count - 1
                        }

                        HoverHandler {
                            id: rowHover
                            onHoveredChanged: if (hovered) shell.selectedIndex = index
                        }
                        TapHandler {
                            onTapped: shell.applyWallpaper(wallPath)
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:           parent.left
                            anchors.leftMargin:     14
                            spacing: 12

                            // Thumbnail
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32; height: 28

                                Rectangle {
                                    anchors.fill: parent; radius: 5
                                    color: Qt.rgba(1,1,1,0.06)
                                    border.color: isCurrent
                                        ? Qt.rgba(0.42, 0.68, 1.0, 0.60)
                                        : Qt.rgba(1,1,1,0.10)
                                    border.width: isCurrent ? 1.5 : 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source:      "file://" + wallPath
                                        fillMode:    Image.PreserveAspectCrop
                                        smooth:      true
                                        asynchronous: true
                                        mipmap:      true
                                    }
                                }

                                // "active" dot
                                Rectangle {
                                    visible: isCurrent
                                    anchors.top:   parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin:   -2
                                    anchors.rightMargin: -2
                                    width: 8; height: 8; radius: 4
                                    color: Qt.rgba(0.42, 0.68, 1.0, 1.0)
                                    border.color: Qt.rgba(0,0,0,0.4); border.width: 1
                                }
                            }

                            // Name + path hint
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text:  wallName
                                    color: Qt.rgba(1,1,1, isSelected ? 0.95 : 0.82)
                                    font.pixelSize: 14; font.family: shell.sf
                                    font.weight: isSelected ? Font.SemiBold : Font.Normal
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }

                                Text {
                                    text: {
                                        // show parent folder as a subtle hint
                                        var parts = wallPath.split("/")
                                        return parts.length >= 2 ? parts[parts.length - 2] : ""
                                    }
                                    visible: text.length > 0 && text !== "walls"
                                    color:   Qt.rgba(1,1,1,0.28)
                                    font.pixelSize: 10; font.family: shell.sf
                                }
                            }

                            // "Now playing" tag on the right
                            Item {
                                visible: isCurrent
                                anchors.verticalCenter: parent.verticalCenter
                                width:  currentTag.implicitWidth + 12
                                height: 16

                                Rectangle {
                                    anchors.fill: parent; radius: 8
                                    color: Qt.rgba(0.42, 0.68, 1.0, 0.18)
                                    border.color: Qt.rgba(0.42, 0.68, 1.0, 0.35); border.width: 1
                                }
                                Text {
                                    id: currentTag
                                    anchors.centerIn: parent
                                    text: "active"
                                    font.family: shell.sf; font.pixelSize: 9
                                    color: Qt.rgba(0.72, 0.88, 1.0, 0.90)
                                }
                            }
                        }
                    }
                }
            }

            // ── Entrance animation ─────────────────────────────
            ParallelAnimation {
                id: entranceAnim
                NumberAnimation {
                    target: searchPill; property: "y"
                    from: win.pillY+14; to: win.pillY; duration: 300
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.2,0.8,0.2,1.0,1.0,1.0]
                }
                NumberAnimation {
                    target: searchPill; property: "opacity"
                    from: 0; to: 1; duration: 220
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
