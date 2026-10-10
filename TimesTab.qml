import QtQuick
import qs.Commons
import qs.Ui
import "Stats.js" as Stats

// Every solve in the session, newest first, with the rolling averages that
// ended on it. The marks in the right-hand column are what a solver scans for:
// which solve was the session best, and which one closed the best Ao5.
Item {
  id: tab

  property var panelRoot: null
  property var editor: null
  readonly property var r: tab.panelRoot

  readonly property int bestIdx: r ? Stats.bestIndex(r.solves) : -1
  readonly property var bestA5: r ? Stats.bestAverage(r.solves, 5) : ({ ms: undefined, end: -1 })
  readonly property var bestA12: r ? Stats.bestAverage(r.solves, 12) : ({ ms: undefined, end: -1 })

  readonly property int colNo: Style.space(42)
  readonly property int colTime: Style.space(86)
  readonly property int colAvg: Style.space(78)

  Row {
    id: head
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(18)

    Repeater {
      model: [
        { t: "#",        w: tab.colNo },
        { t: "time",     w: tab.colTime },
        { t: "ao5",      w: tab.colAvg },
        { t: "ao12",     w: tab.colAvg },
        { t: "scramble", w: 0 }
      ]
      delegate: Text {
        required property var modelData
        width: modelData.w > 0 ? modelData.w
          : head.width - tab.colNo - tab.colTime - tab.colAvg * 2
        text: modelData.t
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.space(1)
        color: r ? r.faintColor : Color.foreground
      }
    }
  }

  PanelSeparator {
    id: headRule
    anchors.top: head.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    foreground: r ? r.fg : Color.foreground
  }

  Text {
    anchors.centerIn: parent
    visible: !r || r.solves.length === 0
    text: "no solves yet — hold space on the timer tab"
    font.family: r ? r.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    color: r ? r.faintColor : Color.foreground
  }

  ListView {
    id: list
    anchors.top: headRule.bottom
    anchors.topMargin: Style.space(3)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    visible: r && r.solves.length > 0
    model: r ? r.rowOrder : []
    currentIndex: r ? r.cursor : 0
    boundsBehavior: Flickable.StopAtBounds

    // Keyboard selection has to drag the viewport with it, or the cursor walks
    // off the bottom and the list looks frozen.
    onCurrentIndexChanged: list.positionViewAtIndex(list.currentIndex, ListView.Contain)

    delegate: Rectangle {
      id: row
      required property int modelData
      required property int index
      readonly property var solve: r && row.modelData < r.solves.length ? r.solves[row.modelData] : null
      readonly property bool selected: r && r.cursor === row.index
      readonly property bool isBest: row.modelData === tab.bestIdx && row.modelData >= 0
      readonly property bool underTarget: {
        if (!r || r.targetMs === null || !row.solve) return false
        var e = Stats.effective(row.solve)
        return e !== null && e <= r.targetMs
      }

      width: list.width
      height: Style.space(21)
      color: row.selected ? Style.selectedFill : (rowMouse.containsMouse ? Style.hoverFill : "transparent")

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (r) r.cursor = row.index
      }

      Row {
        anchors.fill: parent

        Text {
          width: tab.colNo
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: row.modelData + 1
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: r ? r.faintColor : Color.foreground
        }

        Text {
          width: tab.colTime
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          text: Stats.fmtSolve(row.solve, r ? r.decimals : 2)
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          font.bold: row.isBest
          color: {
            if (!r) return Color.foreground
            if (Stats.isDnf(row.solve)) return Color.urgent
            if (row.isBest) return Color.accent
            if (row.underTarget) return Util.alpha(Color.accent, 0.85)
            return r.fg
          }
        }

        Text {
          width: tab.colAvg
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          readonly property var a: r ? Stats.averageAt(r.solves, 5, row.modelData) : undefined
          text: a === undefined ? "" : (a === null ? "DNF" : Stats.fmt(a, r ? r.decimals : 2))
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: r ? (row.modelData === tab.bestA5.end ? Color.accent : r.mutedColor) : Color.foreground
        }

        Text {
          width: tab.colAvg
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          readonly property var a: r ? Stats.averageAt(r.solves, 12, row.modelData) : undefined
          text: a === undefined ? "" : (a === null ? "DNF" : Stats.fmt(a, r ? r.decimals : 2))
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: r ? (row.modelData === tab.bestA12.end ? Color.accent : r.mutedColor) : Color.foreground
        }

        Text {
          width: parent.width - tab.colNo - tab.colTime - tab.colAvg * 2
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: {
            if (!row.solve) return ""
            var scr = String(row.solve.scramble || "").replace(/\n/g, "  ")
            var note = String(row.solve.note || "")
            var marks = []
            if (row.modelData === tab.bestA5.end) marks.push("best ao5")
            if (row.modelData === tab.bestA12.end) marks.push("best ao12")
            var tail = marks.length > 0 ? "   [" + marks.join(" · ") + "]" : ""
            return (note !== "" ? "“" + note + "”   " : "") + scr + tail
          }
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          color: r ? r.faintColor : Color.foreground
        }
      }
    }
  }
}
