import QtQuick
import qs.Commons
import qs.Ui
import "Stats.js" as Stats

// The solving surface in the card. Everything it draws -- the clock text, the
// pace line, the sparkline -- is computed once on the panel root so that this
// and FullscreenTimer can never disagree about what the session looks like.
Item {
  id: tab

  property var panelRoot: null
  readonly property var r: tab.panelRoot

  readonly property int n: r ? r.previewN : 0
  readonly property int cell: tab.n > 0
    ? Math.max(3, Math.min(Style.space(13), Math.floor(Style.space(124) / (4 * tab.n))))
    : 0
  readonly property int faceGap: Style.space(3)
  readonly property int netWidth: tab.n > 0 ? tab.n * tab.cell * 4 + tab.faceGap * 3 : 0
  readonly property int netHeight: tab.n > 0 ? tab.n * tab.cell * 3 + tab.faceGap * 2 : 0

  // ---- scramble preview, right-hand column
  Item {
    id: previewBox
    visible: tab.n > 0 && r && r.previewNet !== null
    anchors.top: parent.top
    anchors.right: parent.right
    width: visible ? Math.max(tab.netWidth, previewLabel.implicitWidth) : 0
    height: visible ? tab.netHeight + previewLabel.height + Style.space(5) : 0

    Text {
      id: previewLabel
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      text: "AFTER SCRAMBLE"
      font.family: r ? r.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: Style.space(1)
      color: r ? r.faintColor : Color.foreground
    }

    Item {
      anchors.top: previewLabel.bottom
      anchors.topMargin: Style.space(5)
      anchors.horizontalCenter: parent.horizontalCenter
      width: tab.netWidth
      height: tab.netHeight

      Repeater {
        model: r ? r.netLayout : []

        delegate: Grid {
          id: faceGrid
          required property var modelData
          readonly property string faceId: faceGrid.modelData.face

          x: faceGrid.modelData.col * (tab.n * tab.cell + tab.faceGap)
          y: faceGrid.modelData.row * (tab.n * tab.cell + tab.faceGap)
          columns: tab.n
          spacing: 0

          Repeater {
            model: tab.n * tab.n
            delegate: Rectangle {
              required property int index
              width: tab.cell
              height: tab.cell
              color: r ? r.stickerColor(faceGrid.faceId, index) : "transparent"
              border.width: 1
              border.color: Qt.rgba(0, 0, 0, 0.35)
            }
          }
        }
      }
    }
  }

  // ---- left column
  Item {
    id: main
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    anchors.rightMargin: previewBox.visible ? previewBox.width + Style.space(16) : 0

    Text {
      id: scrambleText
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      text: r ? r.scramble : ""
      font.family: r ? r.fontFamily : Style.font.family
      font.pixelSize: Style.font.subtitle
      font.letterSpacing: Style.space(1)
      lineHeight: 1.35
      color: r ? r.fg : Color.foreground
    }

    Text {
      id: scrambleKind
      anchors.top: scrambleText.bottom
      anchors.topMargin: Style.space(3)
      anchors.left: parent.left
      visible: r !== null && r.scrambler === ""
      text: "random-move · not WCA random-state"
      font.family: r ? r.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      color: r ? r.faintColor : Color.foreground
    }

    // ---- the clock
    Item {
      anchors.top: scrambleKind.bottom
      anchors.bottom: readout.top
      anchors.left: parent.left
      anchors.right: parent.right

      Text {
        id: bigTime
        anchors.centerIn: parent
        text: r ? r.displayText : ""
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Math.round(Style.font.displayLarge * 2.1 * (r ? r.timerScale : 1))
        font.bold: true
        color: r ? r.phaseColor : Color.foreground
      }

      Text {
        anchors.top: bigTime.bottom
        anchors.topMargin: Style.space(2)
        anchors.horizontalCenter: bigTime.horizontalCenter
        visible: text !== ""
        text: r ? r.hintText : ""
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        color: r ? r.mutedColor : Color.foreground
      }
    }

    // ---- the numbers
    Column {
      id: readout
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(6)

      Row {
        spacing: Style.space(22)

        Repeater {
          model: r ? r.summary : []

          delegate: Row {
            required property var modelData
            spacing: Style.space(5)

            Text {
              text: parent.modelData.label
              font.family: r ? r.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              font.capitalization: Font.AllUppercase
              font.letterSpacing: Style.space(1)
              color: r ? r.faintColor : Color.foreground
            }

            Text {
              text: parent.modelData.value === undefined || parent.modelData.value === null
                ? "—" : Stats.fmt(parent.modelData.value, r ? r.decimals : 2)
              font.family: r ? r.fontFamily : Style.font.family
              font.pixelSize: Style.font.subtitle
              color: r ? r.fg : Color.foreground
            }
          }
        }
      }

      // ---- session shape. Bars run from the session's fastest to its
      //      slowest rather than from zero: at this spread, zero-based bars
      //      would all be the same height and say nothing.
      Row {
        id: sparkRow
        visible: r !== null && r.spark.length > 1
        height: Style.space(30)
        spacing: Math.max(1, Style.space(1))

        Repeater {
          model: r ? r.spark : []

          delegate: Item {
            required property var modelData
            width: Math.max(2, Math.floor((main.width - Style.space(40)) / Math.max(1, r.spark.length)) - Math.max(1, Style.space(1)))
            height: sparkRow.height

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              radius: Style.cornerRadius > 0 ? 1 : 0
              height: {
                if (parent.modelData.dnf) return sparkRow.height
                var span = r.sparkHi - r.sparkLo
                var frac = span > 0 ? (parent.modelData.ms - r.sparkLo) / span : 0.5
                return Math.max(Style.space(3), Style.space(3) + frac * (sparkRow.height - Style.space(3)))
              }
              color: {
                if (parent.modelData.dnf) return Util.alpha(Color.urgent, 0.75)
                if (r.targetMs !== null && parent.modelData.ms <= r.targetMs) return Util.alpha(Color.accent, 0.85)
                if (parent.modelData.ms === r.sparkLo) return Color.accent
                return Util.alpha(r.fg, 0.45)
              }
            }
          }
        }
      }

      Row {
        spacing: Style.space(20)

        Text {
          visible: text !== ""
          text: r ? r.paceText : ""
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: r ? (r.paceText.indexOf("out of reach") >= 0 ? r.faintColor : Color.accent)
                   : Color.foreground
        }

        Text {
          visible: text !== ""
          text: r ? r.targetText : ""
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: r ? r.mutedColor : Color.foreground
        }
      }
    }
  }
}
