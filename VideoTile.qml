import QtQuick
import QtMultimedia
import qs.Commons

// Video preview tile, kept in its own file because it is the only part of the
// plugin that needs QtMultimedia. DropOverlay loads it through a Loader: if
// qt6-multimedia is missing only this tile goes missing and the overlay still
// opens with posters. The player is constructed only while the Loader is
// active, so decoders are released as soon as the preview rule stops holding.
Item {
  id: root

  property string source: ""

  MediaPlayer {
    id: player
    source: root.source ? Util.fileUrl(root.source) : ""
    autoPlay: true
    loops: MediaPlayer.Infinite
    videoOutput: out
    audioOutput: AudioOutput {
      muted: true
      volume: 0
    }
  }

  VideoOutput {
    id: out
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectCrop
  }
}
