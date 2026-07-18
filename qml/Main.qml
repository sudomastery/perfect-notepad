import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Dialogs
import dev.pnotepad

ApplicationWindow {
    id: root
    width: 1000
    height: 680
    visible: true
    color: ui.base
    // The tab strip acts as the title bar, like Windows 11 Notepad
    flags: Qt.Window | Qt.FramelessWindowHint
    title: {
        var tab = currentTab()
        if (!tab)
            return "pnotepad"
        return (tab.modified ? "● " : "") + tab.title + " - pnotepad"
    }

    // ---------- theme: Windows 11 Notepad (Fluent) ----------

    QtObject {
        id: ui
        property string themeName: "Dark"

        // base: window chrome (mica), surface: editor and active tab,
        // popup: menus/tooltips/panels, field: text inputs
        readonly property var themes: ({
            "Dark": { dark: true, base: "#202020", surface: "#282828", hover: "#2D2D2D",
                      hoverStrong: "#383838", text: "#E8E8E8", textMuted: "#9D9D9D",
                      border: "#3D3D3D", accent: "#4CC2FF", popup: "#2C2C2C", field: "#2D2D2D" },
            "Light": { dark: false, base: "#F3F3F3", surface: "#FFFFFF", hover: "#EAEAEA",
                       hoverStrong: "#E0E0E0", text: "#1B1B1B", textMuted: "#5D5D5D",
                       border: "#E5E5E5", accent: "#005FB8", popup: "#F9F9F9", field: "#FFFFFF" },
            "Claude": { dark: false, base: "#F0EEE6", surface: "#FAF9F5", hover: "#E8E6DC",
                        hoverStrong: "#DDDBCF", text: "#3D3929", textMuted: "#7D7C74",
                        border: "#E0DED2", accent: "#D97757", popup: "#FFFFFF", field: "#FFFFFF" },
            "Dracula": { dark: true, base: "#21222C", surface: "#282A36", hover: "#343746",
                         hoverStrong: "#44475A", text: "#F8F8F2", textMuted: "#8B90AF",
                         border: "#44475A", accent: "#BD93F9", popup: "#282A36", field: "#343746" },
            "Nord": { dark: true, base: "#2E3440", surface: "#3B4252", hover: "#434C5E",
                      hoverStrong: "#4C566A", text: "#ECEFF4", textMuted: "#93A0B5",
                      border: "#4C566A", accent: "#88C0D0", popup: "#3B4252", field: "#434C5E" },
            "Gruvbox": { dark: true, base: "#1D2021", surface: "#282828", hover: "#32302F",
                         hoverStrong: "#3C3836", text: "#EBDBB2", textMuted: "#A89984",
                         border: "#504945", accent: "#FE8019", popup: "#282828", field: "#3C3836" },
            "Solarized Light": { dark: false, base: "#EEE8D5", surface: "#FDF6E3", hover: "#E4DDC8",
                                 hoverStrong: "#D9D2BC", text: "#586E75", textMuted: "#93A1A1",
                                 border: "#D9D2BC", accent: "#268BD2", popup: "#FDF6E3", field: "#FDF6E3" },
            "Monokai": { dark: true, base: "#1E1F1C", surface: "#272822", hover: "#33342E",
                         hoverStrong: "#3E3D32", text: "#F8F8F2", textMuted: "#A59F85",
                         border: "#49483E", accent: "#F92672", popup: "#272822", field: "#33342E" }
        })
        readonly property var themeOrder: ["Dark", "Light", "Claude", "Dracula", "Nord",
                                           "Gruvbox", "Solarized Light", "Monokai"]

        readonly property var t: themes[themeName] !== undefined ? themes[themeName] : themes["Dark"]
        readonly property bool dark: t.dark
        readonly property color base: t.base
        readonly property color surface: t.surface
        readonly property color hover: t.hover
        readonly property color hoverStrong: t.hoverStrong
        readonly property color text: t.text
        readonly property color textMuted: t.textMuted
        readonly property color border: t.border
        readonly property color accent: t.accent
        readonly property color popup: t.popup
        readonly property color field: t.field
        readonly property color selection: Qt.alpha(accent, 0.35)
    }

    property real baseFontSize: Qt.application.font.pointSize > 0 ? Qt.application.font.pointSize : 10
    property real fontSize: baseFontSize + 1
    property string fontChoice: "System"
    property bool wordWrap: true
    property bool findVisible: false
    property bool replaceVisible: false
    property string statusMessage: ""
    property string statusLineCol: "Ln 1, Col 1"
    property int statusChars: 0

    SessionManager { id: session }

    Connections {
        target: session
        function onFilesRequested(pathsJson) {
            var files = JSON.parse(pathsJson)
            for (var i = 0; i < files.length; i++)
                openPath(files[i])
            root.show()
            root.raise()
            root.requestActivate()
        }
    }

    ListModel { id: tabsModel }

    Component.onCompleted: {
        var saved = session.get_theme()
        if (saved === "" )
            ui.themeName = Application.styleHints.colorScheme === Qt.Dark ? "Dark" : "Light"
        else if (saved === "dark")
            ui.themeName = "Dark"
        else if (saved === "light")
            ui.themeName = "Light"
        else if (ui.themes[saved] !== undefined)
            ui.themeName = saved

        var savedFont = session.get_setting("font")
        if (savedFont !== "")
            root.fontChoice = savedFont

        var data = JSON.parse(session.load_session())
        for (var i = 0; i < data.tabs.length; i++) {
            var t = data.tabs[i]
            addTab(t.id, tabTitleFor(t.content, t.file_path), t.file_path,
                   t.content, t.cursor, t.modified)
        }
        if (tabsModel.count === 0)
            newTab()
        else
            tabBar.currentIndex = Math.max(0, Math.min(data.active, tabsModel.count - 1))

        var cli = JSON.parse(session.cli_files())
        for (var j = 0; j < cli.length; j++)
            openPath(cli[j])
        focusEditor()
        session.start_server()
    }

    onClosing: saveAllTabs()

    // ---------- reusable styled controls ----------

    component IconButton: ToolButton {
        id: iconBtn
        implicitWidth: 30
        implicitHeight: 30
        icon.width: 15
        icon.height: 15
        icon.color: iconBtn.hovered ? ui.text : ui.textMuted
        background: Rectangle {
            radius: 4
            color: iconBtn.down ? ui.hoverStrong : iconBtn.hovered ? ui.hover : "transparent"
        }
    }

    component StyledField: TextField {
        id: styledField
        color: ui.text
        placeholderTextColor: ui.textMuted
        selectionColor: ui.selection
        selectedTextColor: ui.text
        leftPadding: 10
        rightPadding: 10
        implicitHeight: 30
        background: Rectangle {
            radius: 4
            color: ui.field
            border.width: 1
            border.color: ui.border
            // Fluent focus underline
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 1
                height: 2
                radius: 1
                color: ui.accent
                visible: styledField.activeFocus
            }
        }
    }

    component FluentButton: Button {
        id: fluentBtn
        implicitHeight: 30
        contentItem: Label {
            text: fluentBtn.text
            color: ui.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 4
            color: fluentBtn.down ? ui.hoverStrong : fluentBtn.hovered ? ui.hover : ui.surface
            border.width: 1
            border.color: ui.border
        }
    }

    component StyledMenuItem: MenuItem {
        id: styledItem
        implicitHeight: 32
        implicitWidth: 240
        contentItem: RowLayout {
            spacing: 0
            Label {
                Layout.leftMargin: 10
                Layout.preferredWidth: 16
                text: (styledItem.checkable && styledItem.checked) || styledItem.showCheck ? "✓" : ""
                color: ui.accent
            }
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                text: styledItem.text
                color: ui.text
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                Layout.rightMargin: styledItem.infoText === "" ? 10 : 4
                text: styledItem.shortcutHint !== undefined ? styledItem.shortcutHint : ""
                color: ui.textMuted
                font.pointSize: root.baseFontSize - 1
            }
            IconButton {
                id: infoBtn
                visible: styledItem.infoText !== "" && styledItem.highlighted
                Layout.rightMargin: 6
                implicitWidth: 22
                implicitHeight: 22
                icon.name: "help-contextual"
                icon.width: 13
                icon.height: 13

                ToolTip {
                    id: infoTip
                    visible: infoBtn.hovered
                    delay: 150
                    contentWidth: 260
                    contentItem: Label {
                        text: styledItem.infoText
                        color: ui.text
                        wrapMode: Text.Wrap
                    }
                    background: Rectangle {
                        color: ui.popup
                        radius: 6
                        border.width: 1
                        border.color: ui.border
                    }
                }
            }
        }
        property string shortcutHint: ""
        property string infoText: ""
        property bool showCheck: false
        background: Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            radius: 4
            color: styledItem.highlighted ? ui.hover : "transparent"
        }
    }

    component StyledSeparator: MenuSeparator {
        contentItem: Rectangle {
            implicitWidth: 220
            implicitHeight: 1
            color: ui.border
        }
    }

    component WindowButton: ToolButton {
        id: winBtn
        property color hoverColor: ui.hover
        property color hoverIconColor: ui.text
        Layout.fillHeight: true
        Layout.preferredWidth: 44
        icon.width: 12
        icon.height: 12
        icon.color: winBtn.hovered ? hoverIconColor : ui.textMuted
        background: Rectangle {
            color: winBtn.down || winBtn.hovered ? winBtn.hoverColor : "transparent"
        }
    }

    component StatusSegment: RowLayout {
        id: seg
        property string label: ""
        spacing: 0
        Rectangle { width: 1; height: 14; color: ui.border }
        Label {
            text: seg.label
            color: ui.textMuted
            font.pointSize: root.baseFontSize - 1
            leftPadding: 12
            rightPadding: 12
        }
    }

    component StyledMenu: Menu {
        topPadding: 5
        bottomPadding: 5
        background: Rectangle {
            implicitWidth: 250
            color: ui.popup
            radius: 8
            border.width: 1
            border.color: ui.border
        }
    }

    // ---------- helpers ----------

    function toggleMaximize() {
        if (root.visibility === Window.Maximized)
            root.showNormal()
        else
            root.showMaximized()
    }

    function currentTab() {
        return tabBar.currentIndex >= 0 && tabBar.currentIndex < tabsModel.count
                ? tabsModel.get(tabBar.currentIndex) : null
    }

    function currentEditor() {
        var pane = editorRepeater.itemAt(tabBar.currentIndex)
        return pane ? pane.editor : null
    }

    function focusEditor() {
        Qt.callLater(function() {
            var e = currentEditor()
            if (e) e.forceActiveFocus()
        })
    }

    function addTab(id, title, filePath, content, cursor, modified) {
        tabsModel.append({ tabId: id, title: title, filePath: filePath,
                           initialContent: content, initialCursor: cursor,
                           modified: modified })
    }

    function newTab() {
        addTab(session.new_id(), "Untitled", "", "", 0, false)
        tabBar.currentIndex = tabsModel.count - 1
        focusEditor()
    }

    // Open a file by absolute path: focus its tab if already open,
    // otherwise load it into a new tab.
    function openPath(path) {
        for (var i = 0; i < tabsModel.count; i++) {
            if (tabsModel.get(i).filePath === path) {
                tabBar.currentIndex = i
                focusEditor()
                return
            }
        }
        var content = session.read_file(path)
        addTab(session.new_id(), path.substring(path.lastIndexOf("/") + 1),
               path, content, 0, false)
        tabBar.currentIndex = tabsModel.count - 1
        Qt.callLater(function() { saveTabAt(tabBar.currentIndex) })
        focusEditor()
    }

    function tabTitleFor(text, filePath) {
        if (filePath !== "")
            return filePath.substring(filePath.lastIndexOf("/") + 1)
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].trim()
            if (t.length > 0)
                return t.length > 24 ? t.substring(0, 24) + "…" : t
        }
        return "Untitled"
    }

    function saveTabAt(i) {
        var pane = editorRepeater.itemAt(i)
        if (!pane || i >= tabsModel.count)
            return
        var tab = tabsModel.get(i)
        session.save_tab(tab.tabId, tab.filePath, pane.editor.text,
                         pane.editor.cursorPosition, tab.modified)
    }

    function saveAllTabs() {
        for (var i = 0; i < tabsModel.count; i++)
            saveTabAt(i)
        session.set_active(tabBar.currentIndex)
    }

    function closeTab(i) {
        var tab = tabsModel.get(i)
        session.remove_tab(tab.tabId)
        tabsModel.remove(i)
        if (tabsModel.count === 0)
            newTab()
        else if (tabBar.currentIndex >= tabsModel.count)
            tabBar.currentIndex = tabsModel.count - 1
        focusEditor()
    }

    function saveCurrent() {
        var tab = currentTab()
        var e = currentEditor()
        if (!tab || !e)
            return
        if (tab.filePath === "") {
            saveDialog.open()
            return
        }
        if (session.write_file(tab.filePath, e.text)) {
            tabsModel.setProperty(tabBar.currentIndex, "modified", false)
            saveTabAt(tabBar.currentIndex)
            flashStatus("Saved " + tab.filePath)
        } else {
            flashStatus("Could not save " + tab.filePath)
        }
    }

    function insertTimestamp() {
        var e = currentEditor()
        if (!e)
            return
        e.insert(e.cursorPosition, Qt.formatDateTime(new Date(), "h:mm AP M/d/yyyy"))
    }

    function flashStatus(msg) {
        statusMessage = msg
        statusTimer.restart()
    }

    function updateStatus(e) {
        if (!e)
            return
        var before = e.text.substring(0, e.cursorPosition)
        var lastNl = before.lastIndexOf("\n")
        var line = 1
        for (var i = 0; i < before.length; i++)
            if (before.charCodeAt(i) === 10) line++
        statusLineCol = "Ln " + line + ", Col " + (e.cursorPosition - lastNl)
        statusChars = e.text.length
    }

    function escapeRegex(s) {
        return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    }

    function findNext() {
        var e = currentEditor()
        if (!e || findField.text === "")
            return
        var q = findField.text.toLowerCase()
        var t = e.text.toLowerCase()
        var i = t.indexOf(q, e.selectionEnd)
        if (i < 0)
            i = t.indexOf(q, 0)
        if (i >= 0)
            e.select(i, i + q.length)
        else
            flashStatus("\"" + findField.text + "\" not found")
    }

    function findPrev() {
        var e = currentEditor()
        if (!e || findField.text === "")
            return
        var q = findField.text.toLowerCase()
        var t = e.text.toLowerCase()
        var from = e.selectionStart - 1
        var i = from >= 0 ? t.lastIndexOf(q, from) : -1
        if (i < 0)
            i = t.lastIndexOf(q)
        if (i >= 0)
            e.select(i, i + q.length)
        else
            flashStatus("\"" + findField.text + "\" not found")
    }

    function replaceOne() {
        var e = currentEditor()
        if (!e || findField.text === "")
            return
        if (e.selectedText.toLowerCase() === findField.text.toLowerCase()) {
            var s = e.selectionStart
            e.remove(e.selectionStart, e.selectionEnd)
            e.insert(s, replaceField.text)
        }
        findNext()
    }

    function replaceAll() {
        var e = currentEditor()
        if (!e || findField.text === "")
            return
        var re = new RegExp(escapeRegex(findField.text), "gi")
        var matches = e.text.match(re)
        e.text = e.text.replace(re, replaceField.text)
        flashStatus("Replaced " + (matches ? matches.length : 0) + " occurrences")
    }

    Timer {
        id: statusTimer
        interval: 4000
        onTriggered: statusMessage = ""
    }

    // ---------- shortcuts ----------

    Shortcut { sequences: [StandardKey.AddTab, StandardKey.New]; onActivated: newTab() }
    Shortcut { sequence: StandardKey.Close; onActivated: closeTab(tabBar.currentIndex) }
    Shortcut { sequence: StandardKey.Open; onActivated: openDialog.open() }
    Shortcut { sequence: StandardKey.Save; onActivated: saveCurrent() }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: saveDialog.open() }
    Shortcut { sequence: "F5"; onActivated: insertTimestamp() }
    Shortcut {
        sequence: StandardKey.Find
        onActivated: { findVisible = true; findField.forceActiveFocus(); findField.selectAll() }
    }
    Shortcut {
        sequence: "Ctrl+H"
        onActivated: { findVisible = true; replaceVisible = true; findField.forceActiveFocus() }
    }
    Shortcut { sequence: StandardKey.ZoomIn; onActivated: fontSize = Math.min(fontSize + 1, 72) }
    Shortcut { sequence: "Ctrl+="; onActivated: fontSize = Math.min(fontSize + 1, 72) }
    Shortcut { sequence: StandardKey.ZoomOut; onActivated: fontSize = Math.max(fontSize - 1, 5) }
    Shortcut { sequence: "Ctrl+0"; onActivated: fontSize = baseFontSize + 1 }
    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: { tabBar.currentIndex = (tabBar.currentIndex + 1) % tabsModel.count; focusEditor() }
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: {
            tabBar.currentIndex = (tabBar.currentIndex - 1 + tabsModel.count) % tabsModel.count
            focusEditor()
        }
    }
    Shortcut {
        sequence: "Escape"
        enabled: findVisible
        onActivated: { findVisible = false; replaceVisible = false; focusEditor() }
    }

    // ---------- header: tab strip + menu bar ----------

    header: Column {
        Rectangle {
            width: root.width
            height: 42
            color: ui.base

            // Empty strip area moves the window; double-click maximizes
            Item {
                anchors.fill: parent
                TapHandler {
                    onDoubleTapped: root.toggleMaximize()
                }
                DragHandler {
                    target: null
                    onActiveChanged: if (active) root.startSystemMove()
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                spacing: 2

                TabBar {
                    id: tabBar
                    // Size to the tabs so the + button sits right after the last tab
                    Layout.preferredWidth: Math.min(contentWidth, root.width - 60)
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    background: null
                    onCurrentIndexChanged: {
                        updateStatus(currentEditor())
                        session.set_active(currentIndex)
                    }

                    Repeater {
                        model: tabsModel
                        TabButton {
                            id: tabButton
                            width: Math.min(220, implicitWidth + 16)
                            height: 34

                            background: Rectangle {
                                radius: 6
                                color: tabButton.checked ? ui.surface
                                     : tabButton.hovered ? ui.hover : "transparent"
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.MiddleButton
                                onClicked: root.closeTab(index)
                            }

                            contentItem: RowLayout {
                                spacing: 6
                                Rectangle {
                                    Layout.leftMargin: 6
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: ui.accent
                                    visible: model.modified
                                }
                                Label {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: model.modified ? 0 : 6
                                    text: model.title
                                    color: tabButton.checked ? ui.text : ui.textMuted
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                                IconButton {
                                    icon.name: "tab-close"
                                    icon.width: 10
                                    icon.height: 10
                                    implicitWidth: 20
                                    implicitHeight: 20
                                    opacity: tabButton.checked || tabButton.hovered ? 1 : 0
                                    onClicked: root.closeTab(index)
                                }
                            }
                        }
                    }
                }

                IconButton {
                    Layout.alignment: Qt.AlignVCenter
                    icon.name: "list-add"
                    onClicked: newTab()
                    ToolTip.visible: hovered
                    ToolTip.text: "New tab (Ctrl+T)"
                }

                Item { Layout.fillWidth: true }

                WindowButton {
                    icon.name: "window-minimize"
                    onClicked: root.showMinimized()
                }
                WindowButton {
                    icon.name: root.visibility === Window.Maximized ? "window-restore" : "window-maximize"
                    onClicked: root.toggleMaximize()
                }
                WindowButton {
                    icon.name: "window-close"
                    hoverColor: "#C42B1C"
                    hoverIconColor: "#FFFFFF"
                    onClicked: root.close()
                }
            }
        }

        Rectangle {
            width: root.width
            height: 38
            color: ui.base

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 2

                MenuBar {
                    id: menuBar
                    background: null
                    spacing: 2

                    delegate: MenuBarItem {
                        id: mbi
                        implicitHeight: 30
                        contentItem: Label {
                            text: mbi.text
                            color: ui.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: 4
                            color: mbi.highlighted || mbi.down ? ui.hover : "transparent"
                        }
                    }

                    StyledMenu {
                        title: "File"
                        StyledMenuItem { text: "New tab"; shortcutHint: "Ctrl+T"; onTriggered: newTab() }
                        StyledMenuItem { text: "Open…"; shortcutHint: "Ctrl+O"; onTriggered: openDialog.open() }
                        StyledMenuItem { text: "Save"; shortcutHint: "Ctrl+S"; onTriggered: saveCurrent() }
                        StyledMenuItem { text: "Save as…"; shortcutHint: "Ctrl+Shift+S"; onTriggered: saveDialog.open() }
                        StyledSeparator {}
                        StyledMenuItem {
                            text: "Clear dump…"
                            infoText: "Files away all your unsaved notes at once: each one is written "
                                    + "to a folder you pick, named automatically from its content, and "
                                    + "its tab is closed. Notes already saved as files stay open."
                            onTriggered: dumpDialog.open()
                        }
                        StyledSeparator {}
                        StyledMenuItem {
                            text: "Close tab"
                            shortcutHint: "Ctrl+W"
                            onTriggered: closeTab(tabBar.currentIndex)
                        }
                    }

                    StyledMenu {
                        title: "Edit"
                        StyledMenuItem {
                            text: "Undo"
                            shortcutHint: "Ctrl+Z"
                            onTriggered: { var e = currentEditor(); if (e) e.undo() }
                        }
                        StyledMenuItem {
                            text: "Redo"
                            shortcutHint: "Ctrl+Y"
                            onTriggered: { var e = currentEditor(); if (e) e.redo() }
                        }
                        StyledSeparator {}
                        StyledMenuItem {
                            text: "Cut"
                            shortcutHint: "Ctrl+X"
                            onTriggered: { var e = currentEditor(); if (e) e.cut() }
                        }
                        StyledMenuItem {
                            text: "Copy"
                            shortcutHint: "Ctrl+C"
                            onTriggered: { var e = currentEditor(); if (e) e.copy() }
                        }
                        StyledMenuItem {
                            text: "Paste"
                            shortcutHint: "Ctrl+V"
                            onTriggered: { var e = currentEditor(); if (e) e.paste() }
                        }
                        StyledSeparator {}
                        StyledMenuItem {
                            text: "Find"
                            shortcutHint: "Ctrl+F"
                            onTriggered: { findVisible = true; findField.forceActiveFocus() }
                        }
                        StyledMenuItem {
                            text: "Replace"
                            shortcutHint: "Ctrl+H"
                            onTriggered: { findVisible = true; replaceVisible = true; findField.forceActiveFocus() }
                        }
                        StyledSeparator {}
                        StyledMenuItem {
                            text: "Select all"
                            shortcutHint: "Ctrl+A"
                            onTriggered: { var e = currentEditor(); if (e) e.selectAll() }
                        }
                        StyledMenuItem { text: "Time/Date"; shortcutHint: "F5"; onTriggered: insertTimestamp() }
                    }

                    StyledMenu {
                        title: "View"
                        StyledMenuItem { text: "Zoom in"; shortcutHint: "Ctrl+Plus"; onTriggered: fontSize = Math.min(fontSize + 1, 72) }
                        StyledMenuItem { text: "Zoom out"; shortcutHint: "Ctrl+Minus"; onTriggered: fontSize = Math.max(fontSize - 1, 5) }
                        StyledMenuItem { text: "Restore default zoom"; shortcutHint: "Ctrl+0"; onTriggered: fontSize = baseFontSize + 1 }
                        StyledSeparator {}
                        StyledMenuItem {
                            text: "Word wrap"
                            checkable: true
                            checked: root.wordWrap
                            onTriggered: root.wordWrap = checked
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                IconButton {
                    icon.name: "configure"
                    onClicked: settingsMenu.popup()
                    ToolTip.visible: hovered
                    ToolTip.text: "Settings"

                    StyledMenu {
                        id: settingsMenu

                        Label {
                            text: "Theme"
                            color: ui.textMuted
                            font.pointSize: root.baseFontSize - 1
                            leftPadding: 14
                            topPadding: 4
                            bottomPadding: 2
                        }
                        Repeater {
                            model: ui.themeOrder
                            StyledMenuItem {
                                text: modelData
                                showCheck: ui.themeName === modelData
                                onTriggered: {
                                    ui.themeName = modelData
                                    session.set_theme(modelData)
                                }
                            }
                        }

                        StyledSeparator {}

                        Label {
                            text: "Editor font"
                            color: ui.textMuted
                            font.pointSize: root.baseFontSize - 1
                            leftPadding: 14
                            topPadding: 4
                            bottomPadding: 2
                        }
                        StyledMenuItem {
                            text: "System default"
                            showCheck: root.fontChoice === "System"
                            onTriggered: { root.fontChoice = "System"; session.set_setting("font", "System") }
                        }
                        StyledMenuItem {
                            text: "Monospace"
                            showCheck: root.fontChoice === "Monospace"
                            onTriggered: { root.fontChoice = "Monospace"; session.set_setting("font", "Monospace") }
                        }
                        StyledMenuItem {
                            text: "Serif"
                            showCheck: root.fontChoice === "Serif"
                            onTriggered: { root.fontChoice = "Serif"; session.set_setting("font", "Serif") }
                        }
                    }
                }
            }
        }
    }

    // ---------- body: editor surface with floating find panel ----------

    Rectangle {
        anchors.fill: parent
        color: ui.surface

        StackLayout {
            anchors.fill: parent
            currentIndex: tabBar.currentIndex

            Repeater {
                id: editorRepeater
                model: tabsModel

                Item {
                    property alias editor: textArea

                    ScrollView {
                        anchors.fill: parent

                        ScrollBar.vertical: ScrollBar {
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: ui.textMuted
                                opacity: parent.active ? 0.5 : 0.2
                            }
                        }

                        TextArea {
                            id: textArea
                            property bool ready: false

                            wrapMode: root.wordWrap ? TextArea.Wrap : TextArea.NoWrap
                            font.pointSize: root.fontSize
                            font.family: root.fontChoice === "Monospace" ? "monospace"
                                       : root.fontChoice === "Serif" ? "serif"
                                       : Qt.application.font.family
                            color: ui.text
                            selectionColor: ui.selection
                            selectedTextColor: ui.text
                            selectByMouse: true
                            persistentSelection: true
                            padding: 12
                            background: null
                            tabStopDistance: 4 * textMetrics.advanceWidth

                            TextMetrics {
                                id: textMetrics
                                font: textArea.font
                                text: "x"
                            }

                            Component.onCompleted: {
                                text = model.initialContent
                                cursorPosition = Math.min(model.initialCursor, text.length)
                                ready = true
                            }

                            onTextChanged: {
                                if (!ready)
                                    return
                                tabsModel.setProperty(index, "modified", true)
                                tabsModel.setProperty(index, "title",
                                                      root.tabTitleFor(text, model.filePath))
                                autosave.restart()
                                if (index === tabBar.currentIndex)
                                    root.updateStatus(textArea)
                            }

                            onCursorPositionChanged: {
                                if (ready && index === tabBar.currentIndex)
                                    root.updateStatus(textArea)
                            }

                            // Bullet lists: typing "---" at the start of a line
                            // becomes a bullet, Enter continues the list, and
                            // Enter on an empty bullet ends it.
                            Keys.onPressed: (event) => {
                                if (selectedText.length > 0)
                                    return

                                if (event.text === "-") {
                                    var pos = cursorPosition
                                    var lineStart = text.lastIndexOf("\n", pos - 1) + 1
                                    var before = text.substring(lineStart, pos)
                                    if (/^\s*--$/.test(before)) {
                                        var indent = before.length - 2
                                        remove(lineStart + indent, pos)
                                        insert(lineStart + indent, "• ")
                                        cursorPosition = lineStart + indent + 2
                                        event.accepted = true
                                    }
                                    return
                                }

                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && event.modifiers === Qt.NoModifier) {
                                    var p = cursorPosition
                                    var ls = text.lastIndexOf("\n", p - 1) + 1
                                    var le = text.indexOf("\n", p)
                                    if (le < 0)
                                        le = text.length
                                    var m = text.substring(ls, le).match(/^(\s*)• ?(.*)$/)
                                    if (!m)
                                        return
                                    if (m[2].trim() === "") {
                                        remove(ls, le)
                                        cursorPosition = ls
                                    } else {
                                        insert(p, "\n" + m[1] + "• ")
                                        cursorPosition = p + m[1].length + 3
                                    }
                                    event.accepted = true
                                }
                            }
                        }
                    }

                    Timer {
                        id: autosave
                        interval: 700
                        onTriggered: root.saveTabAt(index)
                    }
                }
            }
        }

        // Floating find/replace panel, top right like Windows 11 Notepad
        Rectangle {
            visible: root.findVisible
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 10
            anchors.rightMargin: 22
            width: findRow.implicitWidth + 20
            height: findRow.implicitHeight + 16
            radius: 8
            color: ui.popup
            border.width: 1
            border.color: ui.border
            z: 10

            GridLayout {
                id: findRow
                anchors.centerIn: parent
                columns: 4
                rowSpacing: 6
                columnSpacing: 6

                StyledField {
                    id: findField
                    Layout.preferredWidth: 200
                    placeholderText: "Find"
                    onAccepted: findNext()
                }
                RowLayout {
                    spacing: 2
                    IconButton { icon.name: "go-up"; onClicked: findPrev() }
                    IconButton { icon.name: "go-down"; onClicked: findNext() }
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    icon.name: "window-close"
                    onClicked: { root.findVisible = false; root.replaceVisible = false; focusEditor() }
                }

                StyledField {
                    id: replaceField
                    Layout.preferredWidth: 200
                    placeholderText: "Replace with"
                    visible: root.replaceVisible
                    onAccepted: replaceOne()
                }
                FluentButton { text: "Replace"; visible: root.replaceVisible; onClicked: replaceOne() }
                FluentButton {
                    Layout.columnSpan: 2
                    text: "Replace all"
                    visible: root.replaceVisible
                    onClicked: replaceAll()
                }
            }
        }
    }

    // ---------- footer: status bar ----------

    footer: Rectangle {
        height: 30
        color: ui.base

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: ui.border
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 0

            Label {
                Layout.fillWidth: true
                text: root.statusMessage !== "" ? root.statusMessage
                    : root.statusChars + " characters"
                color: root.statusMessage !== "" ? ui.accent : ui.textMuted
                font.pointSize: root.baseFontSize - 1
                elide: Text.ElideRight
            }

            StatusSegment { label: root.statusLineCol }
            StatusSegment { label: Math.round(root.fontSize / (root.baseFontSize + 1) * 100) + "%" }
            StatusSegment { label: root.wordWrap ? "Wrap" : "No wrap" }
            StatusSegment { label: "Unix (LF)" }
            StatusSegment { label: "UTF-8" }
        }
    }

    // ---------- frameless window resize grips ----------

    component ResizeGrip: MouseArea {
        property int edges: 0
        acceptedButtons: Qt.LeftButton
        visible: root.visibility !== Window.Maximized && root.visibility !== Window.FullScreen
        onPressed: root.startSystemResize(edges)
    }

    Item {
        parent: Overlay.overlay
        anchors.fill: parent
        z: 10000

        ResizeGrip {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 5; edges: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor
        }
        ResizeGrip {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 5; edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor
        }
        ResizeGrip {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 4; edges: Qt.TopEdge; cursorShape: Qt.SizeVerCursor
        }
        ResizeGrip {
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 5; edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor
        }
        ResizeGrip {
            anchors { left: parent.left; top: parent.top }
            width: 10; height: 10; edges: Qt.LeftEdge | Qt.TopEdge; cursorShape: Qt.SizeFDiagCursor
        }
        ResizeGrip {
            anchors { right: parent.right; top: parent.top }
            width: 10; height: 10; edges: Qt.RightEdge | Qt.TopEdge; cursorShape: Qt.SizeBDiagCursor
        }
        ResizeGrip {
            anchors { left: parent.left; bottom: parent.bottom }
            width: 10; height: 10; edges: Qt.LeftEdge | Qt.BottomEdge; cursorShape: Qt.SizeBDiagCursor
        }
        ResizeGrip {
            anchors { right: parent.right; bottom: parent.bottom }
            width: 10; height: 10; edges: Qt.RightEdge | Qt.BottomEdge; cursorShape: Qt.SizeFDiagCursor
        }
    }

    // ---------- dialogs ----------

    function urlToPath(u) {
        var s = String(u)
        if (s.startsWith("file://"))
            s = s.substring(7)
        return decodeURIComponent(s)
    }

    FileDialog {
        id: openDialog
        fileMode: FileDialog.OpenFile
        nameFilters: ["Text files (*.txt *.md *.log)", "All files (*)"]
        onAccepted: openPath(urlToPath(selectedFile))
    }

    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        defaultSuffix: "txt"
        nameFilters: ["Text files (*.txt)", "All files (*)"]
        onAccepted: {
            var path = urlToPath(selectedFile)
            var e = currentEditor()
            if (!e)
                return
            if (session.write_file(path, e.text)) {
                tabsModel.setProperty(tabBar.currentIndex, "filePath", path)
                tabsModel.setProperty(tabBar.currentIndex, "title",
                                      path.substring(path.lastIndexOf("/") + 1))
                tabsModel.setProperty(tabBar.currentIndex, "modified", false)
                saveTabAt(tabBar.currentIndex)
                flashStatus("Saved " + path)
            } else {
                flashStatus("Could not save " + path)
            }
        }
    }

    FolderDialog {
        id: dumpDialog
        title: "Choose a folder for dumped notes"
        onAccepted: {
            saveAllTabs()
            var res = JSON.parse(session.clear_dump(urlToPath(selectedFolder)))
            for (var i = tabsModel.count - 1; i >= 0; i--)
                if (res.closed.indexOf(tabsModel.get(i).tabId) >= 0)
                    tabsModel.remove(i)
            if (tabsModel.count === 0)
                newTab()
            flashStatus("Dumped " + res.dumped + " notes")
        }
    }
}
