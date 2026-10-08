import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar entry point.
//
// Left click summons the drop overlay, right click opens the drop folder in
// the file manager so files can be dragged straight in.
BarWidget {
  id: root
  moduleName: "kaktyc.wallpaper-drop"

  readonly property string dropDir: Quickshell.env("HOME") + "/.config/omarchy/backgrounds/wallpaper-drop"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string tooltipText: "Wallpaper drop — click to open, right-click to open the folder"

  implicitWidth: content.implicitWidth + Style.space(10)
  implicitHeight: barSize

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    OpticalGlyph {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.bar.iconSlot
      height: Style.bar.iconSlot
      text: "󰋩"
      fontFamily: root.fontFamily
      fontSize: Style.font.icon
      color: root.foreground
    }
  }

  MouseArea {
    id: interactionArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton)
        Quickshell.execDetached(["xdg-open", root.dropDir])
      else
        Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "kaktyc.wallpaper-drop", "{}"])
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
