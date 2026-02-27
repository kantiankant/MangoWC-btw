// Spotlight-style launcher
// Run with: quickshell -p launcher.qml

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property string sf:  "SF Pro Display"
    readonly property string sfi: "SF Symbols"

    // ── All shared state at ShellRoot ─────────────────────────
    property int    selectedIndex: -1
    property string ghostSuffix:   ""
    property string searchText:    ""
    property bool   clipboardFired: false

    ListModel { id: appModel }
    ListModel { id: filteredModel }

    function filterModel(q) {
        filteredModel.clear()
        shell.selectedIndex = -1
        shell.ghostSuffix   = ""
        shell.searchText    = q
        if (q === "") return
        const ql = q.toLowerCase()
        for (let i = 0; i < appModel.count && filteredModel.count < 50; i++) {
            const e = appModel.get(i)
            if (e.appName.toLowerCase().startsWith(ql))
                filteredModel.append({ appName: e.appName, appExec: e.appExec, appIcon: e.appIcon })
        }
        for (let i = 0; i < appModel.count && filteredModel.count < 50; i++) {
            const e = appModel.get(i)
            if (!e.appName.toLowerCase().startsWith(ql) && e.appName.toLowerCase().includes(ql))
                filteredModel.append({ appName: e.appName, appExec: e.appExec, appIcon: e.appIcon })
        }
        if (filteredModel.count > 0) {
            const first = filteredModel.get(0).appName
            shell.ghostSuffix = first.toLowerCase().startsWith(ql) ? first.substring(q.length) : ""
        }
    }

    function launchSelected(fallback) {
        let exec = ""
        if (shell.selectedIndex >= 0 && shell.selectedIndex < filteredModel.count)
            exec = filteredModel.get(shell.selectedIndex).appExec
        else if (filteredModel.count > 0)
            exec = filteredModel.get(0).appExec
        else
            exec = fallback
        if (exec !== "") Quickshell.execDetached(["zsh", "-c", exec])
        Qt.quit()
    }

    function selectUp() {
        if (filteredModel.count === 0) return
        shell.selectedIndex = shell.selectedIndex <= 0 ? filteredModel.count - 1 : shell.selectedIndex - 1
        updateGhost()
    }

    function selectDown() {
        if (filteredModel.count === 0) return
        shell.selectedIndex = shell.selectedIndex >= filteredModel.count - 1 ? 0 : shell.selectedIndex + 1
        updateGhost()
    }

    function updateGhost() {
        if (shell.selectedIndex < 0 || shell.selectedIndex >= filteredModel.count) return
        const name = filteredModel.get(shell.selectedIndex).appName
        shell.ghostSuffix = name.toLowerCase().startsWith(shell.searchText.toLowerCase())
            ? name.substring(shell.searchText.length) : ""
    }

    // ── .desktop parser ────────────────────────────────────────
    Process {
        id: desktopParser
        command: [
            "zsh", "-c",
            // ── 1. Collect all .desktop files (including Flatpak exports) ──
            "find " +
            "  ~/.local/share/applications " +
            "  /usr/share/applications " +
            "  /usr/local/share/applications " +
            "  /var/lib/flatpak/exports/share/applications " +
            "  ~/.local/share/flatpak/exports/share/applications " +
            "  -name '*.desktop' 2>/dev/null | " +

            "while IFS= read -r f; do " +
            "  nodisplay=$(grep -m1 '^NoDisplay' \"$f\" 2>/dev/null | cut -d= -f2); " +
            "  [ \"$nodisplay\" = 'true' ] && continue; " +
            "  type=$(grep -m1 '^Type=' \"$f\" | cut -d= -f2); " +
            "  [ \"$type\" != 'Application' ] && continue; " +
            "  name=$(grep -m1 '^Name=' \"$f\" | cut -d= -f2-); " +
            "  [ -z \"$name\" ] && continue; " +
            "  exec_raw=$(grep -m1 '^Exec=' \"$f\" | cut -d= -f2-); " +
            "  exec=$(echo \"$exec_raw\" | sed 's/ %[fFuUdDnNickvm]//g; s/^env //'); " +
            "  icon_name=$(grep -m1 '^Icon=' \"$f\" | cut -d= -f2-); " +

            // ── 2. Icon resolution ──────────────────────────────────────────
            // If Icon= is already an absolute path to a real file, use it directly.
            "  if [ -f \"$icon_name\" ]; then " +
            "    icon_path=\"$icon_name\"; " +
            "  else " +
            // Build a list of icon search roots, including Flatpak exports.
            // System Flatpak icons:   /var/lib/flatpak/exports/share/icons
            // User Flatpak icons:     ~/.local/share/flatpak/exports/share/icons
            // Flatpak also installs per-app icons under:
            //   /var/lib/flatpak/app/<app-id>/current/active/export/share/icons
            //   ~/.local/share/flatpak/app/<app-id>/current/active/export/share/icons
            // We resolve those by globbing on the icon name itself below.
            "    icon_path=$(find " +
            // WhiteSur (preferred theme) — scalable + 48px
            "      /usr/share/icons/WhiteSur/apps/scalable " +
            "      /usr/share/icons/WhiteSur/apps/48 " +
            "      /usr/share/icons/WhiteSur-dark/apps/scalable " +
            "      /usr/share/icons/WhiteSur-dark/apps/48 " +
            "      ~/.local/share/icons/WhiteSur/apps/scalable " +
            "      ~/.local/share/icons/WhiteSur/apps/48 " +
            // hicolor fallback
            "      /usr/share/icons/hicolor/scalable/apps " +
            "      /usr/share/icons/hicolor/48x48/apps " +
            "      /usr/share/icons/hicolor/128x128/apps " +
            "      /usr/share/icons/hicolor/256x256/apps " +
            // System-wide Flatpak icon exports (all sizes/themes in one tree)
            "      /var/lib/flatpak/exports/share/icons " +
            // User Flatpak icon exports
            "      ~/.local/share/flatpak/exports/share/icons " +
            // pixmaps last resort
            "      /usr/share/pixmaps " +
            "      \\( -name \"${icon_name}.svg\" -o -name \"${icon_name}.png\" -o -name \"${icon_name}.xpm\" \\) " +
            "      2>/dev/null | " +
            // Prefer SVG, then largest PNG — sort: svg first, then by numeric size desc
            "      awk 'BEGIN{s=\"\";p=\"\"} " +
            "           /\\.svg$/{if(s==\"\")s=$0; next} " +
            "           /\\.png$/{if(p==\"\")p=$0} " +
            "           END{print (s!=\"\"?s:p)}'); " +

            // ── 3. Flatpak per-app bundle icon fallback ─────────────────────
            // Some Flatpaks don't export to the shared icon tree at all and
            // only ship icons inside their own app bundle.  We glob for them.
            "    if [ -z \"$icon_path\" ]; then " +
            "      icon_path=$(find " +
            "        /var/lib/flatpak/app " +
            "        ~/.local/share/flatpak/app " +
            "        -path \"*/export/share/icons/*\" " +
            "        \\( -name \"${icon_name}.svg\" -o -name \"${icon_name}.png\" \\) " +
            "        2>/dev/null | head -1); " +
            "    fi; " +

            // ── 4. Generic application icon last-ditch fallback ─────────────
            "    if [ -z \"$icon_path\" ]; then " +
            "      icon_path=$(find " +
            "        /usr/share/icons/WhiteSur " +
            "        /usr/share/icons/WhiteSur-dark " +
            "        -name 'application-x-executable.svg' -o -name 'application.svg' " +
            "        2>/dev/null | head -1); " +
            "    fi; " +
            "  fi; " +

            "  printf '%s\\x1f%s\\x1f%s\\n' \"$name\" \"$exec\" \"${icon_path:-}\"; " +
            "done | sort -u -t$'\\x1f' -k1,1"
        ]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const parts = line.split("\x1f")
                if (parts.length >= 2 && parts[0].trim() !== "")
                    appModel.append({
                        appName: parts[0].trim(),
                        appExec: parts[1].trim(),
                        appIcon: (parts.length >= 3 && parts[2].trim() !== "")
                                 ? "file://" + parts[2].trim() : ""
                    })
            }
        }
    }

    // ── Clipboard ──────────────────────────────────────────────
    Process {
        id: clipboardProc
        command: ["wl-paste", "--no-newline"]
        running: false
        stdout: SplitParser {
            onRead: text => {
                if (shell.clipboardFired) return
                shell.clipboardFired = true
                const q = text.trim()
                if (q !== "")
                    Quickshell.execDetached(["chromium", `https://www.google.com/search?q=${encodeURIComponent(q)}`])
                Qt.quit()
            }
        }
    }

    function fireClipboard() {
        if (shell.clipboardFired) return
        shell.clipboardFired = true
        clipboardProc.running = true
    }

    // ──────────────────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            property var modelData
            screen: modelData

            WlrLayershell.layer:         WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace:     "spotlight-launcher"

            anchors.top:    true
            anchors.bottom: true
            anchors.left:   true
            anchors.right:  true
            color:          "transparent"
            exclusiveZone:  0

            readonly property real barCY:      height * 0.5 - height * 0.12
            readonly property real pillW:      480
            readonly property real pillH:      56
            readonly property real pillX:      width * 0.5 - (pillW + 12 + 4 * 52) * 0.5
            readonly property real pillY:      barCY - pillH * 0.5
            readonly property real iconsX:     pillX + pillW + 12
            readonly property int  maxVisible: 8
            readonly property int  itemH:      44

            // Target height the dropdown wants to be
            readonly property real dropTargetH: filteredModel.count > 0 && shell.searchText !== ""
                ? Math.min(filteredModel.count, win.maxVisible) * win.itemH + 12
                : 0

            Component.onCompleted: {
                entranceAnim.start()
                searchInput.forceActiveFocus()
            }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    if (mouseX >= win.pillX && mouseX <= win.pillX + win.pillW &&
                        mouseY >= win.pillY && mouseY <= win.pillY + win.pillH + dropdown.height)
                        { mouse.accepted = false; return }
                    for (let i = 0; i < 4; i++) {
                        const cx = win.iconsX + i * 52 + 26, cy = win.barCY
                        const dx = mouseX - cx, dy = mouseY - cy
                        if (dx*dx + dy*dy <= 22*22) { mouse.accepted = false; return }
                    }
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

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "􀊫"; font.family: shell.sfi; font.pixelSize: 17
                        font.weight: Font.Medium; color: Qt.rgba(1,1,1,0.12)
                    }

                    Item {
                        width: win.pillW - 18 - 24 - 8 - 18
                        height: win.pillH
                        anchors.verticalCenter: parent.verticalCenter

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
                            color:    Qt.rgba(1,1,1,0.12)
                        }

                        TextField {
                            id: searchInput
                            anchors.fill:         parent
                            background:           null
                            color:                Qt.rgba(1,1,1,0.92)
                            placeholderText:      "Spotlight Search"
                            placeholderTextColor: Qt.rgba(1,1,1,0.30)
                            font.pixelSize: 16; font.family: shell.sf; font.weight: Font.Medium
                            leftPadding: 0; rightPadding: 0
                            verticalAlignment: TextInput.AlignVCenter

                            onTextChanged:      shell.filterModel(text.trim())
                            Keys.onUpPressed:   shell.selectUp()
                            Keys.onDownPressed: shell.selectDown()
                            Keys.onTabPressed: {
                                if (filteredModel.count > 0) {
                                    const idx = shell.selectedIndex >= 0 ? shell.selectedIndex : 0
                                    const name = filteredModel.get(idx).appName
                                    searchInput.text = name
                                    searchInput.cursorPosition = name.length
                                    shell.selectedIndex = idx
                                    shell.ghostSuffix = ""
                                }
                            }
                            Keys.onReturnPressed: shell.launchSelected(text.trim())
                            Keys.onEscapePressed: Qt.quit()
                        }
                    }
                }
            }

            // ── Dropdown ───────────────────────────────────────
            // Positioned as a sibling of searchPill, NOT inside a
            // clipping parent — that was killing it every time.
            // Height is animated so it slides open/closed smoothly.
            Rectangle {
                id: dropdown
                x:      win.pillX
                y:      win.pillY + win.pillH   // flush against the pill — no gap
                width:  win.pillW
                topLeftRadius:     0
                topRightRadius:    0
                bottomLeftRadius: 30 
                bottomRightRadius: 30 
                // Animated height — bezier (0.2, 0.8, 0.2, 1)
                height: 0
                Behavior on height {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.2, 0.8, 0.2, 1.0, 1.0, 1.0]
                    }
                }
                // Drive height from parent property
                Component.onCompleted: height = Qt.binding(() => win.dropTargetH)

                color:        Qt.rgba(0,0,0,0.12)
                border.color: Qt.rgba(1,1,1,0.10)
                border.width: 1
                clip:         true
                opacity:      searchPill.opacity   // inherits entrance fade
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
                        required property string appName
                        required property string appExec
                        required property string appIcon

                        width:  resultsView.width
                        height: win.itemH

                        Rectangle {
                            anchors.fill:        parent
                            anchors.leftMargin:  4
                            anchors.rightMargin: 4
                            radius: 10
                            color: index === shell.selectedIndex ? Qt.rgba(1,1,1,0.14)
                                 : rowHover.hovered              ? Qt.rgba(1,1,1,0.07)
                                 : "transparent"
                            Behavior on color { ColorAnimation { duration: 80 } }
                        }

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
                            onTapped: { Quickshell.execDetached(["zsh", "-c", appExec]); Qt.quit() }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:           parent.left
                            anchors.leftMargin:     14
                            spacing: 12

                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28; height: 28

                                Image {
                                    id: rowIcon
                                    anchors.fill: parent
                                    source:       appIcon
                                    fillMode:     Image.PreserveAspectFit
                                    smooth:       true
                                    asynchronous: true
                                    visible:      status === Image.Ready
                                }

                                // WhiteSur fallback — application-x-executable style
                                Rectangle {
                                    anchors.fill:  parent
                                    radius:        7
                                    visible:       rowIcon.status !== Image.Ready
                                    color:         Qt.rgba(1,1,1,0.08)
                                    border.color:  Qt.rgba(1,1,1,0.15)
                                    border.width:  1

                                    Text {
                                        anchors.centerIn: parent
                                        text:             "􀏗"   // square.grid.2x2 — generic app
                                        font.family:      shell.sfi
                                        font.pixelSize:   16
                                        color:            Qt.rgba(1,1,1,0.50)
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text:           appName
                                color:          Qt.rgba(1,1,1, index === shell.selectedIndex ? 0.95 : 0.78)
                                font.pixelSize: 15; font.family: shell.sf
                                font.weight:    index === shell.selectedIndex ? Font.SemiBold : Font.Normal
                            }
                        }
                    }
                }
            }

            // ── Floating icon circles ──────────────────────────

            Item {
                id: ic1; x: win.iconsX; y: win.barCY-28; width: 52; height: 56; opacity: 0
                Rectangle {
                    anchors.centerIn: parent; width: 44; height: 44; radius: 22
                    color: ic1h.hovered ? Qt.rgba(0,0,0,0.12) : Qt.rgba(0,0,0,0.12)
                    border.color: Qt.rgba(1,1,1,0.12); border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: ">_"; font.family: shell.sfi
                        font.pixelSize: 19; font.weight: Font.Medium; color: Qt.rgba(1,1,1,0.80) }
                }
                HoverHandler { id: ic1h }
                TapHandler { onTapped: { Quickshell.execDetached(["ghostty"]); Qt.quit() } }
                Rectangle {
                    anchors.bottom: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 8; visible: ic1h.hovered
                    color: Qt.rgba(0,0,0,0.12); radius: 7
                    width: ict1.width+16; height: ict1.height+10
                    Text { id: ict1; anchors.centerIn: parent; text: "Terminal"
                        color: Qt.rgba(1,1,1,0.88); font.pixelSize: 12
                        font.family: shell.sf; font.weight: Font.Medium }
                }
            }

            Item {
                id: ic2; x: win.iconsX+52; y: win.barCY-28; width: 52; height: 56; opacity: 0
                Rectangle {
                    anchors.centerIn: parent; width: 44; height: 44; radius: 22
                    color: ic2h.hovered ? Qt.rgba(0,0,0,0.12) : Qt.rgba(0,0,0,0.12)
                    border.color: Qt.rgba(1,1,1,0.12); border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "􀈖"; font.family: shell.sfi
                        font.pixelSize: 19; font.weight: Font.Medium; color: Qt.rgba(1,1,1,0.80) }
                }
                HoverHandler { id: ic2h }
                TapHandler { onTapped: { Quickshell.execDetached(["nautilus"]); Qt.quit() } }
                Rectangle {
                    anchors.bottom: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 8; visible: ic2h.hovered
                    color: Qt.rgba(0,0,0,0.12); radius: 7
                    width: ict2.width+16; height: ict2.height+10
                    Text { id: ict2; anchors.centerIn: parent; text: "Files"
                        color: Qt.rgba(1,1,1,0.88); font.pixelSize: 12
                        font.family: shell.sf; font.weight: Font.Medium }
                }
            }

            Item {
                id: ic3; x: win.iconsX+104; y: win.barCY-28; width: 52; height: 56; opacity: 0
                Rectangle {
                    anchors.centerIn: parent; width: 44; height: 44; radius: 22
                    color: ic3h.hovered ? Qt.rgba(0,0,0,0.12) : Qt.rgba(0,0,0,0.12)
                    border.color: Qt.rgba(1,1,1,0.12); border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "􀏺"; font.family: shell.sfi
                        font.pixelSize: 19; font.weight: Font.Medium; color: Qt.rgba(1,1,1,0.80) }
                }
                HoverHandler { id: ic3h }
                TapHandler { onTapped: { Quickshell.execDetached(["chromium"]); Qt.quit() } }
                Rectangle {
                    anchors.bottom: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 8; visible: ic3h.hovered
                    color: Qt.rgba(0,0,0,0.12); radius: 7
                    width: ict3.width+16; height: ict3.height+10
                    Text { id: ict3; anchors.centerIn: parent; text: "Chromium"
                        color: Qt.rgba(1,1,1,0.88); font.pixelSize: 12
                        font.family: shell.sf; font.weight: Font.Medium }
                }
            }

            Item {
                id: ic4; x: win.iconsX+156; y: win.barCY-28; width: 52; height: 56; opacity: 0
                Rectangle {
                    anchors.centerIn: parent; width: 44; height: 44; radius: 22
                    color: ic4h.hovered ? Qt.rgba(0,0,0,0.12) : Qt.rgba(0,0,0,0.12)
                    border.color: Qt.rgba(1,1,1,0.12); border.width: 1
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "􀉃"; font.family: shell.sfi
                        font.pixelSize: 19; font.weight: Font.Medium; color: Qt.rgba(1,1,1,0.80) }
                }
                HoverHandler { id: ic4h }
                TapHandler { onTapped: shell.fireClipboard() }
                Rectangle {
                    anchors.bottom: parent.top; anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: 8; visible: ic4h.hovered
                    color: Qt.rgba(0,0,0,0.12); radius: 7
                    width: ict4.width+16; height: ict4.height+10
                    Text { id: ict4; anchors.centerIn: parent; text: "Search clipboard"
                        color: Qt.rgba(1,1,1,0.88); font.pixelSize: 12
                        font.family: shell.sf; font.weight: Font.Medium }
                }
            }

            // ── Entrance animation ─────────────────────────────
            ParallelAnimation {
                id: entranceAnim
                NumberAnimation { target: searchPill; property: "y"
                    from: win.pillY+14; to: win.pillY; duration: 300
                    easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2,0.8,0.2,1.0,1.0,1.0] }
                NumberAnimation { target: searchPill; property: "opacity"
                    from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    PauseAnimation { duration: 40 }
                    ParallelAnimation {
                        NumberAnimation { target: ic1; property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { target: ic1; property: "y"
                            from: win.barCY-18; to: win.barCY-28; duration: 260
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2,0.8,0.2,1.0,1.0,1.0] }
                    }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 75 }
                    ParallelAnimation {
                        NumberAnimation { target: ic2; property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { target: ic2; property: "y"
                            from: win.barCY-18; to: win.barCY-28; duration: 260
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2,0.8,0.2,1.0,1.0,1.0] }
                    }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 110 }
                    ParallelAnimation {
                        NumberAnimation { target: ic3; property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { target: ic3; property: "y"
                            from: win.barCY-18; to: win.barCY-28; duration: 260
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2,0.8,0.2,1.0,1.0,1.0] }
                    }
                }
                SequentialAnimation {
                    PauseAnimation { duration: 145 }
                    ParallelAnimation {
                        NumberAnimation { target: ic4; property: "opacity"; from: 0; to: 1; duration: 200 }
                        NumberAnimation { target: ic4; property: "y"
                            from: win.barCY-18; to: win.barCY-28; duration: 260
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0.2,0.8,0.2,1.0,1.0,1.0] }
                    }
                }
            }
        }
    }
}
