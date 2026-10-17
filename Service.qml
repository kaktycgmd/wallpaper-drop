import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Wallpaper Drop service: plays a looping, muted video on the Wayland
// background layer (namespace "wallpaper-drop-background"), one PanelWindow
// per connected monitor, above the first-party static wallpaper.
//
// Uses an A/B double-buffer pair of MediaPlayer + VideoOutput per screen so
// switching clips never leaves a blank frame: the incoming clip loads into
// the idle pair and cross-fades in once it delivers a frame.
//
// IPC (omarchy-shell kaktyc.wallpaper-drop <method> [args]):
//   play <path>   — play the clip on every monitor, looping, muted
//   stop          — stop video everywhere, static wallpaper shows through
//   status        — JSON: { enabled, videoPath, playing }
//
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "kaktyc.wallpaper-drop"

  property string videoPath: ""
  property bool enabled: false

  property var activePanels: []

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      screen: modelData
      visible: true
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      updatesEnabled: true

      WlrLayershell.namespace: "wallpaper-drop-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore

      readonly property string monName: String(modelData.name)
      readonly property bool shouldPlay: root.enabled && root.videoPath !== ""

      // ---- A/B double buffer ----
      property bool frontIsA: true
      readonly property var frontPlayer: frontIsA ? playerA : playerB
      readonly property var backPlayer: frontIsA ? playerB : playerA
      property string frontUrl: ""
      property string pendingUrl: ""
      readonly property int fadeMs: 220

      VideoOutput {
        id: outA
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        opacity: panel.frontIsA ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: panel.fadeMs; easing.type: Easing.InOutQuad } }
      }

      VideoOutput {
        id: outB
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        opacity: panel.frontIsA ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: panel.fadeMs; easing.type: Easing.InOutQuad } }
      }

      MediaPlayer {
        id: playerA
        videoOutput: outA
        loops: MediaPlayer.Infinite
        playbackRate: 1.0
        audioOutput: AudioOutput { muted: true; volume: 0 }
        source: ""
      }

      MediaPlayer {
        id: playerB
        videoOutput: outB
        loops: MediaPlayer.Infinite
        playbackRate: 1.0
        audioOutput: AudioOutput { muted: true; volume: 0 }
        source: ""
      }

      Connections {
        target: outA.videoSink
        enabled: panel.pendingUrl !== "" && !panel.frontIsA
        function onVideoFrameChanged() { panel.crossOver() }
      }
      Connections {
        target: outB.videoSink
        enabled: panel.pendingUrl !== "" && panel.frontIsA
        function onVideoFrameChanged() { panel.crossOver() }
      }

      Timer {
        id: swapTimeout
        interval: 4000
        repeat: false
        onTriggered: if (panel.pendingUrl !== "") panel.crossOver()
      }

      Timer {
        id: retire
        interval: panel.fadeMs + 60
        repeat: false
        property var victim: null
        onTriggered: {
          if (victim) { victim.stop(); victim.source = "" }
          victim = null
        }
      }

      function crossOver() {
        if (panel.pendingUrl === "") return
        swapTimeout.stop()
        panel.frontUrl = panel.pendingUrl
        panel.pendingUrl = ""
        panel.frontIsA = !panel.frontIsA
        retire.victim = panel.frontPlayer === playerA ? playerB : playerA
        retire.restart()
        Qt.callLater(panel.sync)
      }

      function sync() {
        var p = panel.frontPlayer
        if (panel.frontUrl === "") { p.stop(); p.source = ""; return }
        if (panel.shouldPlay) {
          if (p.playbackState !== MediaPlayer.PlayingState) p.play()
        } else {
          if (p.playbackState === MediaPlayer.PlayingState) p.pause()
        }
      }

      function requestUrl(url) {
        if (url === "") {
          swapTimeout.stop()
          panel.pendingUrl = ""
          panel.frontUrl = ""
          playerA.stop(); playerB.stop()
          playerA.source = ""; playerB.source = ""
          return
        }
        if (url === panel.pendingUrl) return
        if (url === panel.frontUrl) {
          if (panel.pendingUrl !== "") {
            swapTimeout.stop()
            panel.pendingUrl = ""
            panel.backPlayer.stop()
            panel.backPlayer.source = ""
          }
          panel.sync()
          return
        }
        if (panel.frontUrl === "") {
          panel.frontUrl = url
          panel.frontPlayer.source = url
          Qt.callLater(panel.sync)
          return
        }
        panel.pendingUrl = url
        panel.backPlayer.source = url
        panel.backPlayer.play()
        swapTimeout.restart()
      }

      readonly property string wantUrl: root.shouldPlay ? root.videoUrl : ""
      onWantUrlChanged: panel.requestUrl(wantUrl)
      onShouldPlayChanged: panel.sync()
      Component.onCompleted: {
        root.activePanels.push(panel)
        panel.requestUrl(panel.wantUrl)
      }
    }
  }

  property string videoUrl: {
    if (!videoPath) return ""
    var s = String(videoPath)
    if (s.indexOf("://") !== -1) return s
    return "file://" + s.replace(/ /g, "%20")
  }

  onVideoPathChanged: {
    if (root.enabled && root.videoPath !== "") {
      Qt.callLater(function() {
        var url = root.videoUrl
        for (var i = 0; i < root.activePanels.length; i++)
          root.activePanels[i].requestUrl(url)
      })
    } else {
      for (var i = 0; i < root.activePanels.length; i++)
        root.activePanels[i].requestUrl("")
    }
  }

  onEnabledChanged: {
    if (root.enabled && root.videoPath !== "") {
      Qt.callLater(function() {
        var url = root.videoUrl
        for (var i = 0; i < root.activePanels.length; i++)
          root.activePanels[i].requestUrl(url)
      })
    } else {
      for (var i = 0; i < root.activePanels.length; i++)
        root.activePanels[i].requestUrl("")
    }
  }

  IpcHandler {
    target: root.pluginId

    function play(path: string): void {
      root.videoPath = String(path || "").trim()
      root.enabled = true
    }

    function stop(): void {
      root.enabled = false
      root.videoPath = ""
    }

    function status(): string {
      return JSON.stringify({
        enabled: root.enabled,
        videoPath: root.videoPath,
        playing: root.enabled && root.videoPath !== ""
      })
    }
  }
}
