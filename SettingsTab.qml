import QtQuick
import qs.Commons
import qs.Ui
import "Scramble.js" as Scramble
import "Stats.js" as Stats

// Everything adjustable, in one scrolling column, written straight through to
// config.json as it changes. No save button: a timer is a thing you fiddle
// with between solves, and a change you have to confirm is a change you forget
// to confirm.
Item {
  id: tab

  property var panelRoot: null
  readonly property var r: tab.panelRoot
  readonly property color fg: r ? r.fg : Color.foreground
  readonly property string ff: r ? r.fontFamily : Style.font.family

  Flickable {
    id: scroll
    anchors.fill: parent
    contentHeight: form.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: form
      width: scroll.width
      spacing: Style.space(8)

      // ---- event + scrambling
      PanelSectionHeader {
        text: "SCRAMBLE"
        foreground: tab.fg
        fontFamily: tab.ff
      }

      Row {
        spacing: Style.space(14)

        Dropdown {
          width: Style.spacing.dropdownWidth
          label: "Event"
          fontFamily: tab.ff
          options: Scramble.puzzleNames()
          value: r ? r.puzzle.name : ""
          onChanged: function (v) { if (r) r.setSessionPuzzle(Scramble.idForName(v)) }
        }

        NumberField {
          label: "Length (0 = event default)"
          fontFamily: tab.ff
          foreground: tab.fg
          from: 0
          to: 200
          stepSize: 1
          value: r ? r.scrambleLength : 0
          onModified: function (v) { if (r) r.setOpt("scrambleLength", v) }
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Built-in scrambles are random-move. For WCA random-state scrambles, give a command "
            + "below that prints one scramble on stdout — its output is used verbatim."
        font.family: tab.ff
        font.pixelSize: Style.font.caption
        color: r ? r.faintColor : Color.foreground
      }

      Row {
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(120)
          text: "External scrambler"
          font.family: tab.ff
          font.pixelSize: Style.font.bodySmall
          color: r ? r.mutedColor : Color.foreground
        }

        TextField {
          id: scramblerField
          width: Style.space(380)
          foreground: tab.fg
          placeholderText: "e.g. tnoodle-scramble 333"
          text: r ? r.scrambler : ""
          onEditingFinished: if (r) r.setOpt("scrambler", text)
          onAccepted: {
            if (r) { r.setOpt("scrambler", text); r.newScramble() }
          }
        }
      }

      PanelSeparator { width: parent.width; foreground: tab.fg }

      // ---- the clock itself
      PanelSectionHeader {
        text: "TIMER"
        foreground: tab.fg
        fontFamily: tab.ff
      }

      Toggle {
        width: parent.width
        label: "WCA inspection"
        description: "Space starts a countdown first; over the limit is +2, two seconds past that is a DNF"
        foreground: tab.fg
        fontFamily: tab.ff
        checked: r ? r.inspection : false
        onClicked: if (r) r.setOpt("inspection", !r.inspection)
      }

      Row {
        spacing: Style.space(14)

        NumberField {
          label: "Inspection seconds"
          fontFamily: tab.ff
          foreground: tab.fg
          from: 1
          to: 120
          stepSize: 1
          value: r ? r.inspectionSeconds : 15
          onModified: function (v) { if (r) r.setOpt("inspectionSeconds", v) }
        }

        NumberField {
          label: "Hold before ready (ms)"
          fontFamily: tab.ff
          foreground: tab.fg
          from: 0
          to: 2000
          stepSize: 50
          value: r ? r.holdMs : 300
          onModified: function (v) { if (r) r.setOpt("holdMs", v) }
        }

        NumberField {
          label: "Target seconds (0 = none)"
          fontFamily: tab.ff
          foreground: tab.fg
          from: 0
          to: 3600
          stepSize: 1
          value: r && r.targetMs !== null ? Math.round(r.targetMs / 1000) : 0
          onModified: function (v) { if (r) r.setOpt("targetSeconds", v) }
        }
      }

      Row {
        spacing: Style.space(20)

        Column {
          spacing: Style.space(3)
          Text {
            text: "Decimals"
            font.family: tab.ff
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.space(1)
            color: r ? r.faintColor : Color.foreground
          }
          ButtonGroup {
            options: ["2", "3"]
            value: r ? String(r.decimals) : "2"
            foreground: tab.fg
            fontFamily: tab.ff
            focusable: false
            onChanged: function (v) { if (r) r.setOpt("decimals", parseInt(v, 10)) }
          }
        }

        Column {
          spacing: Style.space(3)
          Text {
            text: "In the bar"
            font.family: tab.ff
            font.pixelSize: Style.font.caption
            font.capitalization: Font.AllUppercase
            font.letterSpacing: Style.space(1)
            color: r ? r.faintColor : Color.foreground
          }
          ButtonGroup {
            options: ["icon", "last", "ao5", "count"]
            value: r ? r.barDisplay : "last"
            foreground: tab.fg
            fontFamily: tab.ff
            focusable: false
            onChanged: function (v) { if (r) r.setOpt("barDisplay", v) }
          }
        }
      }

      Row {
        spacing: Style.space(10)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(120)
          text: "Clock size"
          font.family: tab.ff
          font.pixelSize: Style.font.bodySmall
          color: r ? r.mutedColor : Color.foreground
        }

        PanelSlider {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(220)
          height: Style.space(20)
          bar: r ? r.bar : null
          minimum: 0.5
          maximum: 2.5
          step: 0.1
          value: r ? r.timerScale : 1.0
          onMoved: function (v) { if (r) r.setOpt("timerScale", Math.round(v * 10) / 10) }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: (r ? r.timerScale.toFixed(1) : "1.0") + "×"
          font.family: tab.ff
          font.pixelSize: Style.font.bodySmall
          color: r ? r.mutedColor : Color.foreground
        }
      }

      Toggle {
        width: parent.width
        label: "Hide the time while solving"
        description: "Removes the pressure of a running clock; the solve is still measured"
        foreground: tab.fg
        fontFamily: tab.ff
        checked: r ? r.hideWhileRunning : false
        onClicked: if (r) r.setOpt("hideWhileRunning", !r.hideWhileRunning)
      }

      Toggle {
        width: parent.width
        label: "Scramble preview"
        description: "Draws the scrambled state as a net, for 2x2 through 7x7"
        foreground: tab.fg
        fontFamily: tab.ff
        checked: r ? r.showPreview : true
        onClicked: if (r) r.setOpt("showPreview", !r.showPreview)
      }

      Toggle {
        width: parent.width
        label: "Announce personal bests"
        description: "A desktop notification when a single, Ao5, or Ao12 record falls"
        foreground: tab.fg
        fontFamily: tab.ff
        checked: r ? r.notifyPB : true
        onClicked: if (r) r.setOpt("notifyPB", !r.notifyPB)
      }

      PanelSeparator { width: parent.width; foreground: tab.fg }

      // ---- sessions
      PanelSectionHeader {
        text: "SESSION"
        foreground: tab.fg
        fontFamily: tab.ff
      }

      Row {
        spacing: Style.space(14)

        Dropdown {
          width: Style.spacing.dropdownWidth
          label: "Current"
          fontFamily: tab.ff
          options: r ? Stats.sessionNames(r.store) : []
          value: r ? Stats.sessionNames(r.store)[r.store.current] : ""
          onChanged: function (v) {
            if (!r) return
            var names = Stats.sessionNames(r.store)
            for (var i = 0; i < names.length; i++) if (names[i] === v) { r.selectSession(i); return }
          }
        }

        TextField {
          id: renameField
          width: Style.space(200)
          foreground: tab.fg
          placeholderText: "rename — Enter to apply"
          text: r && r.session ? r.session.name : ""
          onAccepted: if (r) r.renameSession(text)
        }
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: "New session"
          bordered: true
          foreground: tab.fg
          fontFamily: tab.ff
          onClicked: if (r) r.addSession()
        }

        Button {
          text: "Export CSV"
          bordered: true
          foreground: tab.fg
          fontFamily: tab.ff
          onClicked: if (r) r.exportCsv()
        }

        Button {
          text: "Clear times"
          bordered: true
          foreground: Color.urgent
          fontFamily: tab.ff
          onClicked: if (r) r.clearConfirmOpen = true
        }

        Button {
          text: "Delete session"
          bordered: true
          foreground: Color.urgent
          fontFamily: tab.ff
          onClicked: if (r) r.deleteConfirmOpen = true
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: {
          if (!r) return ""
          return "Solves live in ~/.local/state/pyang.cubetimer/sessions.json; these settings in "
               + "config.json beside it. Defaults for a fresh install come from this widget's entry "
               + "in ~/.config/omarchy/shell.json."
        }
        font.family: tab.ff
        font.pixelSize: Style.font.caption
        color: r ? r.faintColor : Color.foreground
      }

      Item { width: 1; height: Style.space(6) }
    }
  }

}
