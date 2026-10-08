import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Wallpaper drop overlay.
//
// A compact panel under the bar button (top right): drag files in from a
// file manager anywhere on screen (or paste them with Ctrl+V), preview them
// in a small grid — GIFs animate, videos decode into the hovered/selected
// tile — and apply with a click. Applying goes through the helper scripts
// next to this file so the backend choice (static background vs.
// motion-wallpaper vs. tenzin vs. the auto color theme) stays out of QML.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string dropDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds/wallpaper-drop"
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "kaktyc.wallpaper-drop"

  property bool opened: false
  property bool loaded: false
  property var items: []
  property string filterText: ""
  property string selectedPath: ""
  property string pendingPath: ""
  property string hoverPath: ""
  property string statusText: ""
  property bool applying: false
  property bool dragInside: false
  property bool rescanQueued: false

  // Keyboard policy: Exclusive while the pointer is over the panel (Esc and
  // typing go to it), OnDemand otherwise so the rest of the desktop keeps
  // the keyboard. Right after opening there is a short Exclusive grace so
  // Esc works before the pointer ever reaches the panel.
  property bool focusExclusive: false
  property bool focusHovered: false

  Timer {
    id: focusGrace
    interval: 200
    onTriggered: if (!root.focusHovered) root.focusExclusive = false
  }

  // Rows are "path\tthumb\tkind", newest first. Filtering is by file name.
  readonly property var visibleItems: {
    var q = filterText.toLowerCase()
    if (!q) return items
    var out = []
    for (var i = 0; i < items.length; i++) {
      if (items[i].path.split("/").pop().toLowerCase().indexOf(q) !== -1) out.push(items[i])
    }
    return out
  }

  function scriptPath(name) {
    return Qt.resolvedUrl(name).toString().replace(/^file:\/\//, "")
  }

  function urlToPath(url) {
    var u = String(url || "")
    if (u.indexOf("file://") !== 0) return ""
    var s = u.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
    return s
  }

  function indexByPath(path) {
    for (var i = 0; i < items.length; i++) if (items[i].path === path) return i
    return -1
  }

  function indexOfVisible(path) {
    for (var i = 0; i < visibleItems.length; i++) if (visibleItems[i].path === path) return i
    return -1
  }

  function syncGridIndex() {
    var idx = indexOfVisible(selectedPath)
    if (idx >= 0 && grid.currentIndex !== idx) grid.currentIndex = idx
  }

  function syncSelectionFromIndex() {
    var it = visibleItems[grid.currentIndex]
    if (it && it.path !== selectedPath) selectedPath = it.path
  }

  function ensureSelection() {
    if (visibleItems.length === 0) {
      selectedPath = ""
      return
    }
    if (indexOfVisible(selectedPath) !== -1) return
    selectedPath = visibleItems[0].path
    syncGridIndex()
  }

  function loadRows(rows) {
    var out = []
    var lines = String(rows || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line) continue
      var parts = line.split("\t")
      if (parts.length < 3) continue
      out.push({ path: parts[0], thumb: parts[1], kind: parts[2] })
    }
    items = out
    loaded = true
    if (pendingPath) {
      if (indexByPath(pendingPath) >= 0) selectedPath = pendingPath
      pendingPath = ""
    }
    ensureSelection()
    syncGridIndex()
  }

  function refresh() {
    if (listProc.running) {
      rescanQueued = true
      return
    }
    listProc.command = [scriptPath("list.sh"), dropDir]
    listProc.running = true
  }

  function focusUi() {
    if (grid.visible) grid.forceActiveFocus()
    else card.forceActiveFocus()
  }

  function open(payload) {
    opened = true
    statusText = ""
    filterText = ""
    focusExclusive = true
    focusHovered = false
    focusGrace.restart()
    refresh()
    Qt.callLater(focusUi)
  }

  function close() {
    opened = false
    focusExclusive = false
    hoverPath = ""
    dragInside = false
  }

  function requestClose() {
    if (applying) return
    if (root.shell) root.shell.hide(pluginId)
    else close()
  }

  function handleKey(event) {
    if (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)) return
    if (event.modifiers & Qt.ControlModifier) {
      if (event.key === Qt.Key_V) {
        importClipboard()
        event.accepted = true
      }
      return
    }
    if (event.key === Qt.Key_Escape) {
      if (filterText) filterText = ""
      else requestClose()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      applySelected()
      event.accepted = true
    } else if (event.key === Qt.Key_Delete) {
      if (selectedPath) deletePath(selectedPath)
      event.accepted = true
    } else if (Util.editsFilter(event, filterText)) {
      filterText = Util.editedFilter(event, filterText)
      event.accepted = true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
               || event.key === Qt.Key_Up || event.key === Qt.Key_Down
               || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      // Left to GridView's own navigation; selection follows currentIndex.
    } else if (event.text && event.text.length === 1
               && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
      filterText = filterText + event.text
      event.accepted = true
    }
  }

  function handleUrls(urls) {
    var paths = []
    for (var i = 0; i < urls.length; i++) {
      var p = urlToPath(urls[i])
      if (p) paths.push(p)
    }
    if (paths.length === 0) {
      statusText = "Nothing to import"
      return
    }
    importPaths(paths)
  }

  function importPaths(paths) {
    if (importProc.running || !paths || paths.length === 0) return
    importProc.command = [scriptPath("import.sh")].concat(paths)
    importProc.running = true
    statusText = "Importing…"
  }

  function importClipboard() {
    if (importProc.running) return
    importProc.command = [scriptPath("import.sh"), "--clipboard"]
    importProc.running = true
    statusText = "Pasting…"
  }

  function applySelected() {
    if (selectedPath) applyPath(selectedPath)
  }

  function deletePath(path) {
    if (!path || delProc.running) return
    delProc.command = [scriptPath("delete.sh"), path]
    delProc.running = true
  }

  function applyPath(path) {
    if (applying) return
    applying = true
    statusText = "Applying…"
    hoverPath = ""
    applyProc.command = [scriptPath("apply.sh"), path]
    applyProc.running = true
  }

  onFilterTextChanged: Qt.callLater(function() {
    ensureSelection()
    syncGridIndex()
  })

  onOpenedChanged: {
    if (opened) Qt.callLater(focusUi)
    else hoverPath = ""
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadRows(String(text || ""))
    }
    onExited: {
      if (root.rescanQueued) {
        root.rescanQueued = false
        root.refresh()
      }
    }
  }

  Process {
    id: importProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(l) { return l.length > 0 })
        if (lines.length === 0) {
          root.statusText = "Nothing to import (unsupported file type?)"
        } else {
          root.statusText = lines.length === 1 ? "1 file added" : (lines.length + " files added")
          root.pendingPath = lines[0]
        }
      }
    }
    onExited: root.refresh()
  }

  Process {
    id: applyProc
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.statusText = ""
        if (root.shell) root.shell.hide(root.pluginId)
        else root.close()
      } else if (exitCode === 2) {
        root.statusText = "No video wallpaper backend available"
      } else {
        root.statusText = "Could not apply that wallpaper"
      }
    }
  }

  Process {
    id: delProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() === "active")
          root.statusText = "That is your current wallpaper"
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) root.statusText = "Deleted"
      else if (exitCode === 3) root.statusText = "That is your current wallpaper"
      else if (exitCode !== 0) root.statusText = "Could not delete"
      root.refresh()
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    color: "transparent"
    // Shares the app menu's layer namespace on purpose: the card uses
    // Color.menu.background, the alpha the hyprglass `omarchy-menu` mask
    // threshold (0.34, under the 0.384 composited card surface) was derived
    // for — so the card is glassed, like Super+Space. Opaque thumbnails stay
    // crisp: glass only shows through translucent pixels. See shell.toml
    // [menu] and hyprland.lua hyprglass block.
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive while the pointer is over the panel (see focusExclusive),
    // OnDemand otherwise — an unconditional Exclusive stole every keystroke
    // on the desktop while the panel was open.
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusExclusive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
      : WlrKeyboardFocus.None
    // Reserve nothing, but clear of the bar (same pair omawidgets uses).
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // Sits under the bar, flush with the right island where the button is.
    // The exclusive zone already clears the bar, so the margin is the gap.
    anchors { top: true; right: true }
    margins { top: 16; right: 20 }

    implicitWidth: screen ? Math.min(screen.width - 32, 432) : 432
    implicitHeight: screen ? Math.min(screen.height - 72, 560) : 560

    // Drops land on the panel.
    DropArea {
      id: dropArea
      anchors.fill: parent
      keys: ["text/uri-list"]
      onEntered: root.dragInside = true
      onExited: root.dragInside = false
      onDropped: function(drop) {
        root.dragInside = false
        root.handleUrls(drop.urls)
      }
    }

    Item {
      id: card
      anchors.fill: parent
      focus: true

      // Coexists with the MouseAreas inside: handlers don't take hover from
      // the items they pass over.
      HoverHandler {
        onHoveredChanged: {
          root.focusHovered = hovered
          root.focusExclusive = hovered
        }
      }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) { root.handleKey(event) }

      Rectangle {
        anchors.fill: parent
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 1
      }

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(14)
        anchors.leftMargin: Style.space(14)
        // Leaves room for the close button on the right.
        anchors.rightMargin: Style.space(44)
        height: headerCol.height

        Column {
          id: headerCol
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Wallpaper drop"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }

          Text {
            width: parent.width
            text: root.dropDir + (root.items.length > 0 ? "   ·   " + root.items.length + " files" : "")
            color: Util.alpha(Color.menu.text, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideMiddle
          }

          Text {
            visible: root.filterText !== ""
            text: "Filter: " + root.filterText
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: Font.DemiBold
          }
        }
      }

      // Close: the panel has no outside-click close anymore (the desktop
      // underneath must stay clickable), so the button and Esc do it.
      Item {
        id: closeBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        width: Style.space(24)
        height: Style.space(24)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(6)
          color: closeArea.containsMouse
            ? Util.alpha(Color.accent, 0.25)
            : Util.alpha(Color.foreground, 0.08)
        }

        Text {
          anchors.centerIn: parent
          text: "×"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.weight: Font.DemiBold
        }

        MouseArea {
          id: closeArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestClose()
        }
      }

      Item {
        id: body
        anchors.top: header.bottom
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(14)
        anchors.bottomMargin: Style.space(8)
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)

        Text {
          anchors.centerIn: parent
          visible: !root.loaded
          text: "Loading…"
          color: Util.alpha(Color.menu.text, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(6)
          visible: root.loaded && root.items.length === 0

          Text {
            text: "Drop images or videos here"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.weight: Font.DemiBold
          }

          Text {
            width: body.width - Style.space(16)
            text: "Drag files from your file manager, or press Ctrl+V to paste"
            color: Util.alpha(Color.menu.text, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.loaded && root.items.length > 0 && root.visibleItems.length === 0
          text: "No matches"
          color: Util.alpha(Color.menu.text, 0.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        GridView {
          id: grid
          anchors.fill: parent
          visible: root.loaded && root.visibleItems.length > 0
          clip: true
          focus: true
          model: root.visibleItems
          cellWidth: (width - Style.space(8)) / 3
          cellHeight: Math.round(cellWidth * 0.78)

          onVisibleChanged: if (visible && root.opened) forceActiveFocus()
          onCurrentIndexChanged: root.syncSelectionFromIndex()

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { root.handleKey(event) }

          delegate: Item {
            id: cell
            required property var modelData

            readonly property string path: modelData.path
            readonly property string thumb: modelData.thumb
            readonly property string kind: modelData.kind
            readonly property string baseName: path.split("/").pop()
            readonly property bool isSelected: root.selectedPath === path
            readonly property bool hovered: mouseArea.containsMouse
            readonly property bool isVideo: kind === "video"
            readonly property bool isGif: kind === "gif"
            // At most one clip decodes at a time: the hovered tile, or the
            // selected one while nothing else is hovered.
            readonly property bool previewActive: root.opened && !root.applying
              && (hovered || (isSelected && root.hoverPath === ""))

            width: grid.cellWidth
            height: grid.cellHeight

            Item {
              id: tile
              anchors.fill: parent
              anchors.margins: Style.space(6)

              Rectangle {
                anchors.fill: parent
                color: Util.alpha(Color.foreground, 0.06)
              }

              Image {
                id: poster
                anchors.fill: parent
                source: thumb ? Util.fileUrl(thumb) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: !(cell.isGif && cell.previewActive)
              }

              AnimatedImage {
                anchors.fill: parent
                visible: cell.isGif && cell.previewActive
                source: cell.isGif && cell.previewActive ? Util.fileUrl(cell.path) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Loader {
                id: videoLoader
                anchors.fill: parent
                active: cell.isVideo && cell.previewActive
                source: "VideoTile.qml"
                onLoaded: if (item) item.source = cell.path
              }

              Rectangle {
                visible: cell.isVideo || cell.isGif
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.topMargin: Style.space(6)
                anchors.leftMargin: Style.space(6)
                width: badgeText.width + Style.space(8)
                height: badgeText.height + Style.space(4)
                color: Util.alpha(Color.background, 0.72)

                Text {
                  id: badgeText
                  anchors.centerIn: parent
                  text: cell.isVideo ? "VIDEO" : "GIF"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.weight: Font.DemiBold
                }
              }

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: nameText.height + Style.space(6)
                color: Util.alpha(Color.background, 0.72)

                Text {
                  id: nameText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  text: cell.baseName
                  color: Color.foreground
                  elide: Text.ElideMiddle
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: cell.isSelected ? 2 : 1
                border.color: cell.isSelected
                  ? Color.accent
                  : Util.alpha(Color.foreground, cell.hovered ? 0.5 : 0.2)
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.hoverPath = cell.path
              onExited: if (root.hoverPath === cell.path) root.hoverPath = ""
              onClicked: function(mouse) {
                // Right-click deletes (a copy from the drop folder — the
                // original in the file manager is untouched).
                if (mouse.button === Qt.RightButton) {
                  root.deletePath(cell.path)
                  return
                }
                if (cell.isSelected) root.applyPath(cell.path)
                else {
                  root.selectedPath = cell.path
                  root.syncGridIndex()
                }
              }
            }
          }
        }
      }

      Item {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        anchors.bottomMargin: Style.space(12)
        height: hintText.height

        Text {
          id: statusHint
          visible: root.statusText !== ""
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.statusText
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          id: hintText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Enter apply · type filter · Del/RMB delete · Esc"
          color: Util.alpha(Color.menu.text, 0.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }

      Rectangle {
        anchors.fill: parent
        visible: root.dragInside
        z: 20
        color: Util.alpha(Color.accent, 0.08)
        border.color: Color.accent
        border.width: 2

        Text {
          anchors.centerIn: parent
          text: "Release to add"
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.weight: Font.DemiBold
        }
      }
    }
  }
}
