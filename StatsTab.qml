import QtQuick
import qs.Commons
import qs.Ui
import "Stats.js" as Stats

// Current and best for each average length, the session summary, and the shape
// of the distribution. "Current" is the average ending on the latest solve;
// "best" is the best such window anywhere in the session.
Item {
  id: tab

  property var panelRoot: null
  readonly property var r: tab.panelRoot

  readonly property var lengths: [3, 5, 12, 50, 100]

  function show(v) {
    if (v === undefined) return "—"
    if (v === null) return "DNF"
    return Stats.fmt(v, r ? r.decimals : 2)
  }

  readonly property var hist: r ? Stats.histogram(r.solves, 14) : []
  readonly property int histMax: {
    var m = 0
    for (var i = 0; i < tab.hist.length; i++) if (tab.hist[i].count > m) m = tab.hist[i].count
    return Math.max(1, m)
  }

  // ---- averages table
  Column {
    id: left
    anchors.top: parent.top
    anchors.left: parent.left
    width: Math.floor(parent.width * 0.46)
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "AVERAGES"
      foreground: r ? r.fg : Color.foreground
      fontFamily: r ? r.fontFamily : Style.font.family
    }

    Row {
      Text {
        width: Style.space(70)
        text: ""
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
      Repeater {
        model: ["current", "best"]
        delegate: Text {
          required property string modelData
          width: Style.space(96)
          text: modelData
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.capitalization: Font.AllUppercase
          font.letterSpacing: Style.space(1)
          color: r ? r.faintColor : Color.foreground
        }
      }
    }

    Row {
      Text {
        width: Style.space(70)
        height: Style.space(20)
        verticalAlignment: Text.AlignVCenter
        text: "single"
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        color: r ? r.mutedColor : Color.foreground
      }
      Text {
        width: Style.space(96)
        height: Style.space(20)
        verticalAlignment: Text.AlignVCenter
        text: {
          if (!r || r.solves.length === 0) return "—"
          return Stats.fmtSolve(r.solves[r.solves.length - 1], r.decimals)
        }
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        color: r ? r.fg : Color.foreground
      }
      Text {
        width: Style.space(96)
        height: Style.space(20)
        verticalAlignment: Text.AlignVCenter
        text: tab.show(r ? Stats.best(r.solves) : undefined)
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        color: Color.accent
      }
    }

    Repeater {
      model: tab.lengths

      delegate: Row {
        required property int modelData
        readonly property bool reachable: r !== null && r.solves.length >= modelData

        Text {
          width: Style.space(70)
          height: Style.space(20)
          verticalAlignment: Text.AlignVCenter
          text: (parent.modelData === 3 ? "mo" : "ao") + parent.modelData
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: r ? (parent.reachable ? r.mutedColor : r.faintColor) : Color.foreground
        }
        Text {
          width: Style.space(96)
          height: Style.space(20)
          verticalAlignment: Text.AlignVCenter
          text: tab.show(r ? Stats.currentAverage(r.solves, parent.modelData) : undefined)
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          color: r ? r.fg : Color.foreground
        }
        Text {
          width: Style.space(96)
          height: Style.space(20)
          verticalAlignment: Text.AlignVCenter
          text: tab.show(r ? Stats.bestAverage(r.solves, parent.modelData).ms : undefined)
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          color: Color.accent
        }
      }
    }
  }

  // ---- session summary
  Column {
    id: right
    anchors.top: parent.top
    anchors.left: left.right
    anchors.leftMargin: Style.space(20)
    anchors.right: parent.right
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "SESSION"
      foreground: r ? r.fg : Color.foreground
      fontFamily: r ? r.fontFamily : Style.font.family
    }

    Repeater {
      model: {
        if (!r) return []
        var hit = ""
        if (r.targetMs !== null) {
          var under = 0, counted = 0
          for (var i = 0; i < r.solves.length; i++) {
            var e = Stats.effective(r.solves[i])
            if (e === null) continue
            counted++
            if (e <= r.targetMs) under++
          }
          hit = counted > 0 ? under + " / " + counted + "  (" + Math.round(under * 100 / counted) + "%)" : "—"
        }
        var rows = [
          { k: "event", v: r.puzzle.name },
          { k: "solves", v: String(r.solves.length) },
          { k: "dnf", v: String(Stats.dnfCount(r.solves)) },
          { k: "mean", v: tab.show(Stats.mean(r.solves)) },
          { k: "worst", v: tab.show(Stats.worst(r.solves)) },
          { k: "spread", v: tab.show(Stats.stdev(r.solves)) }
        ]
        if (hit !== "") rows.push({ k: "under target", v: hit })
        return rows
      }

      delegate: Row {
        required property var modelData
        Text {
          width: Style.space(96)
          height: Style.space(20)
          verticalAlignment: Text.AlignVCenter
          text: parent.modelData.k
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          color: r ? r.mutedColor : Color.foreground
        }
        Text {
          height: Style.space(20)
          verticalAlignment: Text.AlignVCenter
          text: parent.modelData.v
          font.family: r ? r.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          color: r ? r.fg : Color.foreground
        }
      }
    }
  }

  // ---- distribution
  Item {
    id: histBox
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.top: left.bottom
    anchors.topMargin: Style.space(14)
    visible: tab.hist.length > 1

    PanelSectionHeader {
      id: histHead
      anchors.top: parent.top
      text: "DISTRIBUTION"
      foreground: r ? r.fg : Color.foreground
      fontFamily: r ? r.fontFamily : Style.font.family
    }

    Row {
      id: histRow
      anchors.top: histHead.bottom
      anchors.topMargin: Style.space(4)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: histAxis.top
      anchors.bottomMargin: Style.space(3)
      spacing: Style.space(2)

      Repeater {
        model: tab.hist

        delegate: Item {
          required property var modelData
          width: Math.max(2, Math.floor((histRow.width - Style.space(2) * (tab.hist.length - 1)) / Math.max(1, tab.hist.length)))
          height: histRow.height

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(1, Math.round(parent.modelData.count / tab.histMax * (histRow.height - Style.space(12))))
            color: r ? Util.alpha(r.fg, 0.4) : Color.foreground
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.max(1, Math.round(parent.modelData.count / tab.histMax * (histRow.height - Style.space(12)))) + Style.space(1)
            visible: parent.modelData.count > 0
            text: parent.modelData.count
            font.family: r ? r.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            color: r ? r.faintColor : Color.foreground
          }
        }
      }
    }

    Row {
      id: histAxis
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(14)

      Text {
        width: parent.width / 2
        text: tab.hist.length > 0 ? Stats.fmt(tab.hist[0].from, r ? r.decimals : 2) : ""
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        color: r ? r.faintColor : Color.foreground
      }
      Text {
        width: parent.width / 2
        horizontalAlignment: Text.AlignRight
        text: tab.hist.length > 0 ? Stats.fmt(tab.hist[tab.hist.length - 1].to, r ? r.decimals : 2) : ""
        font.family: r ? r.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        color: r ? r.faintColor : Color.foreground
      }
    }
  }
}
