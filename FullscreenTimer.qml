import QtQuick
import qs.Commons
import qs.Ui
import "Stats.js" as Stats

// Solo mode. The scramble, the clock, and the few numbers worth glancing at --
// nothing else, at the size of the screen. No tabs: the moment you want the
// times list you want the card back, and `f` returns you to it.
//
// Sizes are fractions of the surface rather than fixed pixels, so this reads
// the same on a laptop panel and on a 4K monitor.
Item {
  id: face

  property var panelRoot: null
  readonly property var r: face.panelRoot

  readonly property int n: r ? r.previewN : 0
  readonly property int cell: face.n > 0
    ? Math.max(4, Math.min(Style.space(20), Math.floor(face.width * 0.16 / (4 * face.n))))
    : 0
  readonly property int faceGap: Style.space(4)
  readonly property int netWidth: face.n > 0 ? face.n * face.cell * 4 + face.faceGap * 3 : 0
  readonly property int netHeight: face.n > 0 ? face.n * face.cell * 3 + face.faceGap * 2 : 0

  readonly property color fg: r ? r.fg : Color.foreground
  readonly property string ff: r ? r.fontFamily : Style.font.family

  // ---- scramble, across the top
  Text {
    id: scrambleText
    anchors.top: parent.top
    anchors.topMargin: Math.round(face.height * 0.07)
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.round(face.width * 0.74)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    text: r ? r.scramble : ""
    font.family: face.ff
    font.pixelSize: Math.max(Style.font.subtitle, Math.round(face.height * 0.030))
    font.letterSpacing: Style.space(2)
    lineHeight: 1.4
    color: face.fg
  }

  Text {
    anchors.top: scrambleText.bottom
    anchors.topMargin: Style.space(6)
    anchors.horizontalCenter: parent.horizontalCenter
    visible: r !== null && r.scrambler === ""
    text: "random-move · not WCA random-state"
    font.family: face.ff
    font.pixelSize: Style.font.caption
    color: r ? r.faintColor : Color.foreground
  }

  // ---- the clock
  Text {
    id: clock
    anchors.centerIn: parent
    text: r ? r.displayText : ""
    font.family: face.ff
    font.pixelSize: Math.round(face.height * 0.26 * (r ? r.timerScale : 1))
    font.bold: true
    color: r ? r.phaseColor : Color.foreground
  }

  Text {
    anchors.top: clock.bottom
    anchors.topMargin: Style.space(4)
    anchors.horizontalCenter: parent.horizontalCenter
    visible: text !== ""
    text: r ? r.hintText : ""
    font.family: face.ff
    font.pixelSize: Math.max(Style.font.body, Math.round(face.height * 0.020))
    color: r ? r.mutedColor : Color.foreground
  }

  // ---- scramble preview, out of the way in the corner
  Item {
    id: previewBox
    visible: face.n > 0 && r && r.previewNet !== null
    anchors.right: parent.right
    anchors.bottom: readout.top
    anchors.rightMargin: Math.round(face.width * 0.05)
    anchors.bottomMargin: Style.space(20)
    width: face.netWidth
    height: face.netHeight

    Repeater {
      model: r ? r.netLayout : []

      delegate: Grid {
        id: faceGrid
        required property var modelData
        readonly property string faceId: faceGrid.modelData.face

        x: faceGrid.modelData.col * (face.n * face.cell + face.faceGap)
        y: faceGrid.modelData.row * (face.n * face.cell + face.faceGap)
        columns: face.n
        spacing: 0

        Repeater {
          model: face.n * face.n
          delegate: Rectangle {
            required property int index
            width: face.cell
            height: face.cell
            color: r ? r.stickerColor(faceGrid.faceId, index) : "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.35)
          }
        }
      }
    }
  }

  // ---- numbers along the bottom
  Column {
    id: readout
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.round(face.height * 0.06)
    anchors.left: parent.left
    anchors.leftMargin: Math.round(face.width * 0.05)
    spacing: Style.space(10)

    Row {
      id: sparkRow
      visible: r !== null && r.spark.length > 1
      height: Math.round(face.height * 0.06)
      spacing: Math.max(1, Style.space(2))

      Repeater {
        model: r ? r.spark : []

        delegate: Item {
          required property var modelData
          width: Math.max(3, Math.round(face.width * 0.30 / Math.max(1, r.spark.length)) - Math.max(1, Style.space(2)))
          height: sparkRow.height

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            radius: Style.cornerRadius > 0 ? 1 : 0
            height: {
              if (parent.modelData.dnf) return sparkRow.height
              var span = r.sparkHi - r.sparkLo
              var frac = span > 0 ? (parent.modelData.ms - r.sparkLo) / span : 0.5
              return Math.max(Style.space(4), Style.space(4) + frac * (sparkRow.height - Style.space(4)))
            }
            color: {
              if (parent.modelData.dnf) return Util.alpha(Color.urgent, 0.75)
              if (r.targetMs !== null && parent.modelData.ms <= r.targetMs) return Util.alpha(Color.accent, 0.85)
              if (parent.modelData.ms === r.sparkLo) return Color.accent
              return Util.alpha(face.fg, 0.45)
            }
          }
        }
      }
    }

    Row {
      spacing: Math.round(face.width * 0.025)

      Repeater {
        model: r ? r.summary : []

        delegate: Row {
          required property var modelData
          spacing: Style.space(7)

          Text {
            text: parent.modelData.label
            font.family: face.ff
            font.pixelSize: Math.max(Style.font.caption, Math.round(face.height * 0.016))
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.space(1)
            color: r ? r.faintColor : Color.foreground
          }

          Text {
            text: parent.modelData.value === undefined || parent.modelData.value === null
              ? "—" : Stats.fmt(parent.modelData.value, r ? r.decimals : 2)
            font.family: face.ff
            font.pixelSize: Math.max(Style.font.subtitle, Math.round(face.height * 0.022))
            color: face.fg
          }
        }
      }
    }

    Row {
      spacing: Math.round(face.width * 0.02)

      Text {
        visible: text !== ""
        text: r ? r.paceText : ""
        font.family: face.ff
        font.pixelSize: Math.max(Style.font.bodySmall, Math.round(face.height * 0.017))
        color: r ? (r.paceText.indexOf("out of reach") >= 0 ? r.faintColor : Color.accent)
                 : Color.foreground
      }

      Text {
        visible: text !== ""
        text: r ? r.targetText : ""
        font.family: face.ff
        font.pixelSize: Math.max(Style.font.bodySmall, Math.round(face.height * 0.017))
        color: r ? r.mutedColor : Color.foreground
      }
    }
  }

  // ---- session label, opposite the numbers
  Text {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Math.round(face.width * 0.05)
    anchors.bottomMargin: Math.round(face.height * 0.06)
    horizontalAlignment: Text.AlignRight
    text: r ? (r.puzzle.name + "  ·  " + (r.session ? r.session.name : "")
               + "  ·  " + r.solves.length + " solves") : ""
    font.family: face.ff
    font.pixelSize: Math.max(Style.font.caption, Math.round(face.height * 0.016))
    color: r ? r.mutedColor : Color.foreground
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(12)
    text: "f or esc leaves fullscreen  ·  space hold → release to start  ·  2 +2  ·  d dnf  ·  x delete  ·  s rescramble"
    font.family: face.ff
    font.pixelSize: Style.font.caption
    color: r ? r.faintColor : Color.foreground
  }
}
