import QtQml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Cube.js" as Cube
import "Scramble.js" as Scramble
import "Stats.js" as Stats

// A speedcubing timer in the bar: hold space, release, solve, hit anything to
// stop. Four tabs -- the timer, the session's times, its statistics, and the
// settings that shape all three.
//
// Three things here that cstimer leaves to the solver:
//
//   * the pace line, which says what the solve in progress has to beat to move
//     the best Ao5 -- the number you actually want mid-session, rather than one
//     you work out afterwards from a table;
//   * personal bests announced through the desktop's own notifications, so a
//     record lands even when the panel is closed;
//   * a scramble preview driven by a real facelet simulation (see Cube.js), for
//     every NxN from 2 to 7 rather than just the small ones.
//
// Settings live in two places on purpose. `~/.config/omarchy/shell.json` holds
// the defaults, because that is the file the rest of the shell is configured
// in and it belongs in a dotfiles repo. The settings tab writes
// `~/.local/state/pyang.cubetimer/config.json`, which overrides shell.json for
// anything changed at runtime -- so a knob can be set once in the config that
// travels, and still be flipped mid-session without editing a file. Solve data
// is separate again, in sessions.json beside it, and is the one file here that
// cannot be regenerated.
Panel {
  id: root
  moduleName: "pyang.cubetimer"
  ipcTarget: "pyang.cubetimer"
  manageIpc: false

  // ---------------------------------------------------------------- settings

  // The WCA scheme, pulled a little off full saturation so six solid blocks
  // next to each other don't fight the theme. Overridable in shell.json for
  // anyone with a differently-stickered cube.
  readonly property var defaultCubeColors: [
    "#e9e9e7",  // U white
    "#c0392b",  // R red
    "#2a9245",  // F green
    "#d9b61c",  // D yellow
    "#d2691e",  // L orange
    "#2b6cb0"   // B blue
  ]

  readonly property var defaults: ({
    puzzle: setting("puzzle", "333"),
    scrambleLength: setting("scrambleLength", 0),
    scrambler: setting("scrambler", ""),
    inspection: setting("inspection", false),
    inspectionSeconds: setting("inspectionSeconds", 15),
    holdMs: setting("holdMs", 300),
    decimals: setting("decimals", 2),
    hideWhileRunning: setting("hideWhileRunning", false),
    showPreview: setting("showPreview", true),
    targetSeconds: setting("targetSeconds", 0),
    notifyPB: setting("notifyPB", true),
    barDisplay: setting("barDisplay", "last"),
    timerScale: setting("timerScale", 1.0),
    cubeColors: setting("cubeColors", defaultCubeColors)
  })

  // Runtime overrides from config.json. `opt` is the only way anything reads a
  // setting, so the precedence (config.json > shell.json > built-in) holds
  // everywhere without each call site remembering it.
  property var cfg: ({})
  property bool cfgLoaded: false

  function opt(key) {
    var v = cfg[key]
    return (v === undefined || v === null) ? defaults[key] : v
  }

  function setOpt(key, value) {
    var next = {}
    for (var k in cfg) next[k] = cfg[k]
    next[key] = value
    cfg = next
    saveConfig()
  }

  readonly property int decimals: opt("decimals") === 3 ? 3 : 2
  readonly property bool inspection: opt("inspection") === true
  readonly property int inspectionSeconds: Math.max(1, Math.round(Number(opt("inspectionSeconds")) || 15))
  readonly property int holdMs: Math.max(0, Math.round(Number(opt("holdMs")) || 0))
  readonly property bool hideWhileRunning: opt("hideWhileRunning") === true
  readonly property bool showPreview: opt("showPreview") !== false
  readonly property bool notifyPB: opt("notifyPB") !== false
  readonly property int scrambleLength: Math.max(0, Math.round(Number(opt("scrambleLength")) || 0))
  readonly property string scrambler: String(opt("scrambler") || "")
  readonly property real timerScale: Math.max(0.4, Math.min(3.0, Number(opt("timerScale")) || 1.0))
  readonly property string barDisplay: String(opt("barDisplay") || "last")
  // 0 means "no target", which is different from a target of zero seconds.
  readonly property var targetMs: {
    var s = Number(opt("targetSeconds")) || 0
    return s > 0 ? s * 1000 : null
  }

  function cubeColor(i) {
    var list = opt("cubeColors")
    if (!Array.isArray(list) || list.length < 6) list = root.defaultCubeColors
    return (i >= 0 && i < 6) ? list[i] : "transparent"
  }

  // ---------------------------------------------------------------- storage

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/pyang.cubetimer"

  property var store: Stats.emptyStore()
  property bool storeLoaded: false

  readonly property var session: store.sessions[Math.min(store.current, store.sessions.length - 1)]
  readonly property var solves: session ? session.solves : []
  // The event belongs to the session rather than to the settings: averaging a
  // 2x2 time into a 5x5 Ao12 would be nonsense, so the two travel together.
  // Each solve still records its own event, so an export stays truthful even
  // for a session whose event was changed halfway through.
  readonly property string puzzleId: session ? session.puzzle : opt("puzzle")
  readonly property var puzzle: Scramble.puzzleById(root.puzzleId)

  // Every mutation goes through here. Deep-copying the store rather than
  // reaching into it is what makes the bindings fire -- QML cannot see a push
  // into a nested array -- and it keeps a half-applied change from ever being
  // written to disk.
  function mutate(fn) {
    if (!storeLoaded) return
    var next = JSON.parse(JSON.stringify(root.store))
    fn(next)
    root.store = Stats.normalizeStore(next)
    saveStore()
  }

  function saveStore() {
    if (!storeLoaded || storeFile.path === "") return
    storeFile.setText(JSON.stringify(root.store, null, 1))
  }

  function saveConfig() {
    if (!cfgLoaded || configFile.path === "") return
    configFile.setText(JSON.stringify(root.cfg, null, 1))
  }

  // ---------------------------------------------------------------- scramble

  property string scramble: ""

  function newScramble() {
    if (root.scrambler !== "") {
      if (scramblerProc.running) return
      scramblerProc.command = ["sh", "-c", root.scrambler]
      scramblerProc.running = true
      return
    }
    root.scramble = Scramble.generate(root.puzzleId, root.scrambleLength, Math.random)
  }

  function builtinScramble() {
    root.scramble = Scramble.generate(root.puzzleId, root.scrambleLength, Math.random)
  }

  onPuzzleIdChanged: if (root.cfgLoaded) root.newScramble()

  readonly property int previewN: root.showPreview ? Scramble.previewSize(root.puzzleId) : 0
  readonly property var previewNet: {
    if (root.previewN <= 0 || root.scramble === "") return null
    return Cube.netFor(root.previewN, Scramble.previewScramble(root.scramble))
  }

  function stickerColor(face, idx) {
    if (!root.previewNet) return "transparent"
    var rows = root.previewNet[face]
    if (!rows) return "transparent"
    var r = Math.floor(idx / root.previewN)
    var c = idx % root.previewN
    return root.cubeColor(rows[r][c])
  }

  // ---------------------------------------------------------------- timing
  //
  // phase: idle -> (inspect) -> hold -> ready -> running -> idle
  //
  // `hold` is the press that has not yet been held long enough; `ready` is the
  // same press once it has. Releasing from `ready` starts the solve, releasing
  // from `hold` abandons it -- which is what makes a twitchy press harmless.
  property string phase: "idle"
  property double startMs: 0
  property double elapsedMs: 0
  property double inspectStartMs: 0
  property double inspectElapsedMs: 0
  property bool heldFromInspect: false
  // After a solve stops, the key that stopped it is still down. Ignoring
  // everything until it comes back up is what stops one keystroke from both
  // ending a solve and starting the next.
  property bool awaitRelease: false
  property string pendingPenalty: ""
  property bool editingNote: false
  property bool clearConfirmOpen: false
  property bool deleteConfirmOpen: false

  // Solo mode: the clock on its own layer surface over everything, for when
  // the session is the only thing happening. The timer state lives on this
  // root, so entering or leaving mid-solve does not disturb a running solve.
  property bool fullscreen: false

  function enterFullscreen() {
    root.fullscreen = true
    root.close()
  }

  function leaveFullscreen() {
    root.fullscreen = false
  }

  function toggleFullscreen() {
    if (root.fullscreen) leaveFullscreen()
    else enterFullscreen()
  }

  // Whichever surface is up owns the keyboard. Both catchers call the same
  // handlers, so this is the only place that has to know which is live.
  readonly property var activeCatcher: root.fullscreen ? fsKeys : keys

  readonly property bool running: root.phase === "running"
  readonly property double inspectRemaining: Math.max(0, root.inspectionSeconds * 1000 - root.inspectElapsedMs)

  Timer {
    id: tick
    interval: 10
    repeat: true
    running: root.phase === "running" || root.phase === "inspect"
    onTriggered: {
      var now = Date.now()
      if (root.phase === "running") {
        root.elapsedMs = now - root.startMs
        return
      }
      root.inspectElapsedMs = now - root.inspectStartMs
      // WCA 2.5: past the inspection limit is +2, past limit + 2s is a DNF.
      // The solve still happens either way; only the result is marked.
      var over = root.inspectElapsedMs - root.inspectionSeconds * 1000
      if (over >= 2000) root.pendingPenalty = Stats.PENALTY_DNF
      else if (over >= 0) root.pendingPenalty = Stats.PENALTY_PLUS2
      else root.pendingPenalty = ""
    }
  }

  Timer {
    id: holdTimer
    interval: Math.max(1, root.holdMs)
    repeat: false
    onTriggered: if (root.phase === "hold") root.phase = "ready"
  }

  function beginHold() {
    if (root.phase === "idle" && root.inspection) {
      root.inspectStartMs = Date.now()
      root.inspectElapsedMs = 0
      root.pendingPenalty = ""
      root.phase = "inspect"
      return
    }
    if (root.phase !== "idle" && root.phase !== "inspect") return
    root.heldFromInspect = (root.phase === "inspect")
    if (root.holdMs <= 0) {
      root.phase = "ready"
    } else {
      root.phase = "hold"
      holdTimer.restart()
    }
  }

  function releaseHold() {
    if (root.phase === "ready") {
      root.startMs = Date.now()
      root.elapsedMs = 0
      root.phase = "running"
    } else if (root.phase === "hold") {
      holdTimer.stop()
      root.phase = root.heldFromInspect ? "inspect" : "idle"
    }
  }

  function stopSolve() {
    var ms = Date.now() - root.startMs
    root.elapsedMs = ms
    root.phase = "idle"
    root.awaitRelease = true
    commitSolve(ms)
    newScramble()
  }

  // Escape during a solve throws it away: a phone ringing mid-solve should not
  // land in the statistics.
  function abortSolve() {
    root.phase = "idle"
    root.awaitRelease = true
    root.elapsedMs = 0
    root.pendingPenalty = ""
  }

  function cancelInspection() {
    root.phase = "idle"
    root.inspectElapsedMs = 0
    root.pendingPenalty = ""
  }

  // ---------------------------------------------------------------- records

  function records() {
    return {
      single: Stats.best(root.solves),
      ao5: Stats.bestAverage(root.solves, 5).ms,
      ao12: Stats.bestAverage(root.solves, 12).ms
    }
  }

  function beat(before, after) {
    if (after === undefined || after === null) return false
    if (before === undefined || before === null) return true
    return after < before
  }

  function commitSolve(ms) {
    var solve = Stats.makeSolve(ms, root.scramble, root.puzzleId, Date.now())
    solve.penalty = root.pendingPenalty
    root.pendingPenalty = ""
    var before = records()
    mutate(function (s) { s.sessions[s.current].solves.push(solve) })
    if (!root.notifyPB) return
    var after = records()
    var parts = []
    if (beat(before.single, after.single)) parts.push("single " + Stats.fmt(after.single, root.decimals))
    if (beat(before.ao5, after.ao5)) parts.push("Ao5 " + Stats.fmt(after.ao5, root.decimals))
    if (beat(before.ao12, after.ao12)) parts.push("Ao12 " + Stats.fmt(after.ao12, root.decimals))
    if (parts.length > 0) {
      notify("Personal best · " + root.puzzle.short,
             root.session.name + " — " + parts.join("  ·  "))
    }
  }

  function notify(title, body) {
    Quickshell.execDetached(["notify-send", "-a", "Cube Timer", "-i", "applications-games", title, body])
  }

  // ---------------------------------------------------------------- editing

  function setPenalty(index, penalty) {
    if (index < 0 || index >= root.solves.length) return
    mutate(function (s) {
      var list = s.sessions[s.current].solves
      // Tapping the penalty that is already set clears it, so the same key
      // both applies and undoes.
      list[index].penalty = (list[index].penalty === penalty) ? Stats.PENALTY_NONE : penalty
    })
  }

  function deleteSolve(index) {
    if (index < 0 || index >= root.solves.length) return
    mutate(function (s) { s.sessions[s.current].solves.splice(index, 1) })
  }

  function setNote(index, text) {
    if (index < 0 || index >= root.solves.length) return
    mutate(function (s) { s.sessions[s.current].solves[index].note = String(text || "") })
  }

  function clearSession() {
    mutate(function (s) { s.sessions[s.current].solves = [] })
  }

  function addSession() {
    mutate(function (s) {
      s.sessions.push(Stats.newSession("Session " + (s.sessions.length + 1), root.puzzleId))
      s.current = s.sessions.length - 1
    })
  }

  function deleteSession() {
    if (root.store.sessions.length <= 1) { clearSession(); return }
    mutate(function (s) {
      s.sessions.splice(s.current, 1)
      if (s.current >= s.sessions.length) s.current = s.sessions.length - 1
    })
  }

  function selectSession(index) {
    mutate(function (s) { s.current = Math.max(0, Math.min(index, s.sessions.length - 1)) })
  }

  function setSessionPuzzle(id) {
    mutate(function (s) { s.sessions[s.current].puzzle = id })
    setOpt("puzzle", id)
  }

  function renameSession(name) {
    var clean = String(name || "").replace(/^\s+|\s+$/g, "")
    if (clean === "") return
    mutate(function (s) { s.sessions[s.current].name = clean })
  }

  property string pendingCsv: ""
  property string pendingCsvPath: ""

  function exportCsv() {
    var slug = String(root.session.name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
    root.pendingCsvPath = root.home + "/cubetimer-" + (slug || "session") + ".csv"
    root.pendingCsv = Stats.csv(root.session, root.decimals)
    exportFile.path = root.pendingCsvPath
    exportTimer.restart()
  }

  // ---------------------------------------------------------------- tabs

  readonly property var tabs: ["timer", "times", "stats", "settings"]
  property string tab: "timer"
  property int cursor: 0

  onTabChanged: {
    if (root.opened && !root.fullscreen) keys.forceActiveFocus()
  }

  function switchTab(delta) {
    var i = root.tabs.indexOf(root.tab)
    if (i < 0) i = 0
    root.tab = root.tabs[(i + delta + root.tabs.length) % root.tabs.length]
  }

  // Newest first, which is the order a solver reads their own times in.
  readonly property var rowOrder: {
    var out = []
    for (var i = root.solves.length - 1; i >= 0; i--) out.push(i)
    return out
  }

  readonly property int cursorSolve: (root.cursor >= 0 && root.cursor < root.rowOrder.length)
    ? root.rowOrder[root.cursor] : -1

  onSolvesChanged: if (root.cursor >= root.rowOrder.length) root.cursor = Math.max(0, root.rowOrder.length - 1)

  // ---------------------------------------------------------------- keys

  function keyPress(e) {
    // A modal is modal: it eats everything, including space, so a held key
    // cannot start a solve behind the scrim.
    if (root.clearConfirmOpen) { e.accepted = clearConfirm.handleKey(e); return }
    if (root.deleteConfirmOpen) { e.accepted = deleteConfirm.handleKey(e); return }
    if (root.editingNote) return
    // Keys.BeforeItem means this handler runs even when a text field or
    // dropdown below has focus. When one does, it owns the keyboard -- not
    // doing this makes the settings tab impossible to type into.
    if (!root.activeCatcher || !root.activeCatcher.activeFocus) return
    if (e.isAutoRepeat) { e.accepted = true; return }

    // While a solve is live nothing else can be reached: that is the point of
    // a timer. Escape is the one exception, and it discards rather than saves.
    if (root.phase === "running") {
      if (e.key === Qt.Key_Escape) abortSolve()
      else stopSolve()
      e.accepted = true
      return
    }

    if (root.awaitRelease) { e.accepted = true; return }

    if (e.key === Qt.Key_Space) {
      beginHold()
      e.accepted = true
      return
    }

    if (e.key === Qt.Key_Escape) {
      if (root.phase === "inspect") cancelInspection()
      else if (root.phase === "hold" || root.phase === "ready") { holdTimer.stop(); root.phase = "idle" }
      else if (root.fullscreen) leaveFullscreen()
      else root.close()
      e.accepted = true
      return
    }

    if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
      switchTab(((e.modifiers & Qt.ShiftModifier) || e.key === Qt.Key_Backtab) ? -1 : 1)
      e.accepted = true
      return
    }

    // The solve a bare penalty key applies to: the one under the cursor on the
    // times tab, the most recent one everywhere else.
    var target = root.tab === "times" ? root.cursorSolve : root.solves.length - 1

    if (e.key === Qt.Key_Down) { moveCursor(1); e.accepted = true; return }
    if (e.key === Qt.Key_Up) { moveCursor(-1); e.accepted = true; return }
    if (e.key === Qt.Key_PageDown) { moveCursor(10); e.accepted = true; return }
    if (e.key === Qt.Key_PageUp) { moveCursor(-10); e.accepted = true; return }
    if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) {
      deleteSolve(target); e.accepted = true; return
    }

    var t = e.text
    if (t === "2") { setPenalty(target, Stats.PENALTY_PLUS2); e.accepted = true; return }
    if (t === "d" || t === "D") { setPenalty(target, Stats.PENALTY_DNF); e.accepted = true; return }
    if (t === "x" || t === "X") { deleteSolve(target); e.accepted = true; return }
    if (t === "f" || t === "F") { toggleFullscreen(); e.accepted = true; return }
    if (t === "s" || t === "S") { newScramble(); e.accepted = true; return }
    if (t === "e" || t === "E") { exportCsv(); e.accepted = true; return }
    if (t === "1") { root.tab = "timer"; e.accepted = true; return }
    if (t === "3") { root.tab = "stats"; e.accepted = true; return }
    if (t === "4") { root.tab = "settings"; e.accepted = true; return }
    if (t === "t" || t === "T") { root.tab = "times"; e.accepted = true; return }
    if (t === "n" || t === "N") {
      if (root.tab === "times" && root.cursorSolve >= 0) {
        noteEditor.text = root.solves[root.cursorSolve].note || ""
        root.editingNote = true
        noteEditor.forceActiveFocus()
        noteEditor.selectAll()
      }
      e.accepted = true
      return
    }
    // Re-use a scramble from the list: the fastest way to retry a case.
    if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.tab === "times" && root.cursorSolve >= 0) {
      root.scramble = root.solves[root.cursorSolve].scramble
      root.tab = "timer"
      e.accepted = true
      return
    }
  }

  function keyRelease(e) {
    if (root.clearConfirmOpen || root.deleteConfirmOpen) return
    if (root.editingNote) return
    if (!root.activeCatcher || !root.activeCatcher.activeFocus) return
    if (e.isAutoRepeat) { e.accepted = true; return }
    if (root.awaitRelease) {
      root.awaitRelease = false
      e.accepted = true
      return
    }
    if (e.key === Qt.Key_Space) {
      releaseHold()
      e.accepted = true
    }
  }

  function moveCursor(delta) {
    if (root.tab !== "times") { root.tab = "times"; return }
    var n = root.rowOrder.length
    if (n === 0) return
    root.cursor = Math.max(0, Math.min(n - 1, root.cursor + delta))
  }

  // ---------------------------------------------------------------- look

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color ruleColor: Util.alpha(fg, 0.14)
  readonly property color mutedColor: Util.alpha(fg, 0.55)
  readonly property color faintColor: Util.alpha(fg, 0.32)

  readonly property color phaseColor: {
    if (root.phase === "ready") return Color.accent
    if (root.phase === "hold") return root.mutedColor
    if (root.phase === "inspect") {
      // The 8-second and 12-second calls a judge would give, in colour.
      var e = root.inspectElapsedMs
      if (e >= (root.inspectionSeconds - 3) * 1000) return Color.urgent
      if (e >= (root.inspectionSeconds - 7) * 1000) return Color.accent
      return root.fg
    }
    return root.fg
  }

  // ---- what the clock reads, in every view
  readonly property string displayText: {
    if (root.phase === "inspect") {
      if (root.pendingPenalty === Stats.PENALTY_DNF) return "DNF"
      if (root.pendingPenalty === Stats.PENALTY_PLUS2) return "+2"
      return String(Math.ceil(root.inspectRemaining / 1000))
    }
    if (root.phase === "running") return root.hideWhileRunning ? "•  •  •" : Stats.fmt(root.elapsedMs, root.decimals)
    if (root.phase === "ready") return "READY"
    if (root.phase === "hold") return "hold"
    var last = root.solves.length > 0 ? root.solves[root.solves.length - 1] : null
    return last ? Stats.fmtSolve(last, root.decimals) : Stats.fmt(0, root.decimals)
  }

  readonly property string hintText: {
    if (root.phase === "ready") return "release to start"
    if (root.phase === "hold") return "keep holding"
    if (root.phase === "inspect") return "inspecting — hold space when ready"
    if (root.phase === "running") return ""
    if (root.awaitRelease) return "let go of the key"
    var last = root.solves.length > 0 ? root.solves[root.solves.length - 1] : null
    if (!last) return root.inspection ? "space starts inspection" : "hold space to begin"
    return "solve " + root.solves.length + "  ·  " + Stats.ago(last.at, root.nowMs)
  }

  // What the solve in progress has to beat. The three outcomes read very
  // differently to a solver, so none of them collapse into "—".
  readonly property string paceText: {
    if (root.solves.length < 4) return ""
    var target = Stats.bestAverage(root.solves, 5).ms
    if (target === undefined) return ""
    var need = Stats.neededFor(root.solves, 5, target)
    if (!need) return ""
    if (need.safe) return "a DNF here still beats your best Ao5"
    if (need.ms === null) return "best Ao5 is out of reach on this solve"
    return "PB Ao5 needs ≤ " + Stats.fmt(need.ms, root.decimals)
  }

  readonly property string targetText: {
    if (root.targetMs === null) return ""
    var under = 0
    var counted = 0
    for (var i = 0; i < root.solves.length; i++) {
      var e = Stats.effective(root.solves[i])
      if (e === null) continue
      counted++
      if (e <= root.targetMs) under++
    }
    if (counted === 0) return "target " + Stats.fmt(root.targetMs, root.decimals)
    return "target " + Stats.fmt(root.targetMs, root.decimals) + "  ·  " + under + "/" + counted
      + " under (" + Math.round(under * 100 / counted) + "%)"
  }

  readonly property var summary: [
    { label: "ao5",  value: Stats.currentAverage(root.solves, 5) },
    { label: "ao12", value: Stats.currentAverage(root.solves, 12) },
    { label: "best", value: Stats.best(root.solves) },
    { label: "mean", value: Stats.mean(root.solves) }
  ]

  // Last forty solves, enough to see a session's shape without the bars going
  // hairline-thin.
  readonly property var spark: {
    var out = []
    var from = Math.max(0, root.solves.length - 40)
    for (var i = from; i < root.solves.length; i++) {
      out.push({ ms: Stats.effective(root.solves[i]), dnf: Stats.isDnf(root.solves[i]) })
    }
    return out
  }

  readonly property real sparkLo: {
    var lo = Infinity
    for (var i = 0; i < root.spark.length; i++) {
      if (root.spark[i].ms !== null && root.spark[i].ms < lo) lo = root.spark[i].ms
    }
    return isFinite(lo) ? lo : 0
  }

  readonly property real sparkHi: {
    var hi = -Infinity
    for (var i = 0; i < root.spark.length; i++) {
      if (root.spark[i].ms !== null && root.spark[i].ms > hi) hi = root.spark[i].ms
    }
    return isFinite(hi) ? hi : 1
  }

  // The standard unfolded net: U above F, D below it, the four sides in a band.
  readonly property var netLayout: [
    { face: "U", col: 1, row: 0 },
    { face: "L", col: 0, row: 1 },
    { face: "F", col: 1, row: 1 },
    { face: "R", col: 2, row: 1 },
    { face: "B", col: 3, row: 1 },
    { face: "D", col: 1, row: 2 }
  ]

  // "4m ago" has to be re-rendered as the minutes pass, not only when a solve
  // lands, so the relative label needs a clock of its own.
  property double nowMs: Date.now()

  Timer {
    interval: 30000
    repeat: true
    running: root.opened || root.fullscreen
    onTriggered: root.nowMs = Date.now()
  }

  readonly property int wantedWidth: Style.space(820)
  readonly property int wantedHeight: Style.space(560)

  // ---------------------------------------------------------------- plumbing

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "pyang.cubetimer"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function scramble(): void { root.newScramble() }
    function fullscreen(): void { root.enterFullscreen() }
    function windowed(): void { root.leaveFullscreen() }
    // Lets a keybinding drop straight onto a tab -- "show me the stats" is a
    // different intent from "open the timer".
    function tab(name: string): void {
      if (root.tabs.indexOf(name) >= 0) {
        root.tab = name
        root.open()
      }
    }
  }

  Process {
    id: mkdirProc
    running: true
    command: ["mkdir", "-p", root.stateDir]
    onExited: {
      configFile.path = root.stateDir + "/config.json"
      storeFile.path = root.stateDir + "/sessions.json"
    }
  }

  // Both files are read before anything is written, and `saveStore` refuses to
  // run until `storeLoaded` is true. Without that guard a slow read would race
  // the first save and truncate a session someone has been building for weeks.
  FileView {
    id: configFile
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.cfg = (parsed && typeof parsed === "object") ? parsed : ({})
      } catch (e) {
        root.cfg = ({})
      }
      root.cfgLoaded = true
      if (root.scramble === "") root.newScramble()
    }
    onLoadFailed: {
      root.cfgLoaded = true
      if (root.scramble === "") root.newScramble()
    }
  }

  FileView {
    id: storeFile
    printErrors: false
    onLoaded: {
      var raw = null
      try { raw = JSON.parse(text()) } catch (e) { raw = null }
      root.store = Stats.normalizeStore(raw)
      root.storeLoaded = true
    }
    // No file means a fresh install, and that is the only moment the `puzzle`
    // setting can apply: from then on the event belongs to the session, and
    // shell.json must not quietly re-point an existing one.
    onLoadFailed: {
      var fresh = Stats.normalizeStore(null)
      fresh.sessions[0].puzzle = root.opt("puzzle")
      root.store = fresh
      root.storeLoaded = true
    }
  }

  FileView {
    id: exportFile
    printErrors: false
  }

  Timer {
    id: exportTimer
    interval: 60
    repeat: false
    onTriggered: {
      exportFile.setText(root.pendingCsv)
      root.notify("Session exported", root.pendingCsvPath)
    }
  }

  Process {
    id: scramblerProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var body = String(text || "").replace(/^\s+|\s+$/g, "")
        if (body.length > 0) root.scramble = body
      }
    }
    onExited: function (code, status) {
      if (code !== 0 || root.scramble === "") root.builtinScramble()
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  onOpenedChanged: if (root.opened && root.scramble === "" && root.cfgLoaded) root.newScramble()

  // ---------------------------------------------------------------- bar

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.caption
    horizontalMargin: 7
    active: root.phase === "running" || root.phase === "inspect"
    text: {
      var glyph = "󰆦"
      if (root.barDisplay === "icon") return glyph
      var last = root.solves.length > 0 ? root.solves[root.solves.length - 1] : null
      if (root.barDisplay === "count") return glyph + " " + root.solves.length
      if (root.barDisplay === "ao5") {
        var a = Stats.currentAverage(root.solves, 5)
        return glyph + " " + (a === undefined ? "—" : Stats.fmt(a, root.decimals))
      }
      return glyph + " " + (last ? Stats.fmtSolve(last, root.decimals) : "—")
    }
    tooltipText: {
      var lines = [root.puzzle.name + " · " + (root.session ? root.session.name : "")]
      lines.push(root.solves.length + " solve" + (root.solves.length === 1 ? "" : "s"))
      var b = Stats.best(root.solves)
      if (b !== undefined) lines.push("best " + Stats.fmt(b, root.decimals))
      var a5 = Stats.currentAverage(root.solves, 5)
      if (a5 !== undefined) lines.push("ao5 " + Stats.fmt(a5, root.decimals))
      var a12 = Stats.currentAverage(root.solves, 12)
      if (a12 !== undefined) lines.push("ao12 " + Stats.fmt(a12, root.decimals))
      return lines.join("\n")
    }
    onPressed: function (b) {
      if (root.fullscreen) root.leaveFullscreen()
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(root.wantedWidth)
    contentHeight: panel.fittedContentHeight(root.wantedHeight, Style.space(900))

    // PanelKeyCatcher has no release handler and no auto-repeat filter, and a
    // hold-to-start timer is nothing but release handling and auto-repeat
    // filtering -- so the dispatch lives here instead.
    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (e) { root.keyPress(e) }
      Keys.onReleased: function (e) { root.keyRelease(e) }

      // ---- header
      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(28)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "CUBE TIMER"
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: Style.space(1)
          color: root.mutedColor
        }

        Text {
          anchors.centerIn: parent
          text: root.puzzle.name + "  ·  " + (root.session ? root.session.name : "")
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          color: root.fg
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.solves.length + " solves"
              + (Stats.dnfCount(root.solves) > 0 ? "  ·  " + Stats.dnfCount(root.solves) + " dnf" : "")
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.faintColor
          }

          PanelActionButton {
            anchors.verticalCenter: parent.verticalCenter
            iconText: "󰊓"
            tooltipText: "Fullscreen (f)"
            foreground: root.mutedColor
            hoverColor: Color.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.iconSmall
            onClicked: root.enterFullscreen()
          }
        }
      }

      // ---- tab strip
      Row {
        id: tabStrip
        anchors.top: header.bottom
        anchors.left: parent.left
        height: Style.space(24)
        spacing: Style.space(18)

        Repeater {
          model: root.tabs
          delegate: Item {
            id: tabItem
            required property string modelData
            readonly property bool current: root.tab === tabItem.modelData
            width: tabLabel.implicitWidth
            height: tabStrip.height

            Text {
              id: tabLabel
              anchors.verticalCenter: parent.verticalCenter
              text: tabItem.modelData
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.letterSpacing: Style.space(1)
              font.capitalization: Font.AllUppercase
              font.bold: tabItem.current
              color: tabItem.current ? root.fg
                : (tabMouse.containsMouse ? Style.hoverStateColor(root.fg, Color.accent) : root.faintColor)
            }

            Rectangle {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: Math.max(1, Style.space(2))
              visible: tabItem.current
              color: Color.accent
            }

            MouseArea {
              id: tabMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.tab = tabItem.modelData
            }
          }
        }
      }

      PanelSeparator {
        id: headRule
        anchors.top: tabStrip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        foreground: root.fg
      }

      // ---- body
      Item {
        id: body
        anchors.top: headRule.bottom
        anchors.topMargin: Style.space(8)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footRule.top
        anchors.bottomMargin: Style.space(6)

        TimerTab {
          anchors.fill: parent
          visible: root.tab === "timer"
          panelRoot: root
        }

        TimesTab {
          anchors.fill: parent
          visible: root.tab === "times"
          panelRoot: root
          editor: noteEditor
        }

        StatsTab {
          anchors.fill: parent
          visible: root.tab === "stats"
          panelRoot: root
        }

        SettingsTab {
          anchors.fill: parent
          visible: root.tab === "settings"
          panelRoot: root
        }
      }

      // The note editor lives outside the tab so its focus survives a redraw
      // of the list, and so `editingNote` has exactly one owner.
      TextField {
        id: noteEditor
        visible: root.editingNote
        anchors.bottom: footRule.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: Style.space(4)
        foreground: root.fg
        placeholderText: "note for this solve — Enter to save, Esc to discard"
        onAccepted: {
          root.setNote(root.cursorSolve, text)
          root.editingNote = false
          keys.forceActiveFocus()
        }
        Keys.onEscapePressed: {
          root.editingNote = false
          keys.forceActiveFocus()
        }
      }

      ConfirmDialog {
        id: clearConfirm
        anchors.fill: parent
        z: 10
        opened: root.clearConfirmOpen
        message: "Delete all " + root.solves.length + " times in “"
          + (root.session ? root.session.name : "") + "”? This cannot be undone."
        confirmText: "Clear"
        background: Color.popups.background
        foreground: root.fg
        fontFamily: root.fontFamily
        // Default the keyboard to Cancel: Enter should not destroy a session
        // for someone who opened this by mistake.
        onOpenedChanged: if (opened) selectedIndex = 0
        onCanceled: root.clearConfirmOpen = false
        onConfirmed: {
          root.clearConfirmOpen = false
          root.clearSession()
        }
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 10
        opened: root.deleteConfirmOpen
        message: root.store.sessions.length <= 1
          ? "This is the only session, so its times will be cleared instead. Continue?"
          : "Delete the session “" + (root.session ? root.session.name : "") + "” and its "
            + root.solves.length + " times?"
        confirmText: "Delete"
        background: Color.popups.background
        foreground: root.fg
        fontFamily: root.fontFamily
        onOpenedChanged: if (opened) selectedIndex = 0
        onCanceled: root.deleteConfirmOpen = false
        onConfirmed: {
          root.deleteConfirmOpen = false
          root.deleteSession()
        }
      }

      PanelSeparator {
        id: footRule
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottomMargin: Style.space(4)
        foreground: root.fg
      }

      Text {
        id: footer
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(16)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: root.faintColor
        text: {
          if (root.phase === "running") return "any key stops  ·  esc discards this solve"
          var common = "space hold → release to start  ·  2 +2  ·  d dnf  ·  x delete  ·  s rescramble  ·  f fullscreen  ·  tab switches"
          if (root.tab === "times") return "↑↓ select  ·  enter re-uses that scramble  ·  n note  ·  " + common
          if (root.tab === "settings") return "e exports csv  ·  " + common
          return common
        }
      }
    }
  }

  // ---------------------------------------------------------------- solo mode
  //
  // Its own layer surface on the overlay layer, so it covers the bar as well
  // as the windows -- a timer with your own status bar still showing is not
  // fullscreen. Keyboard focus is exclusive and the keys route back into the
  // same handlers the card uses, so the state machine has one implementation.
  PanelWindow {
    id: fsWindow
    visible: root.fullscreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-cubetimer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Fully opaque, whatever alpha the theme gives its popups: a wallpaper
    // showing through a running clock is exactly the distraction solo mode
    // exists to remove. No click-to-dismiss either -- a stray click should not
    // end the session you are staring at.
    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 1)
    }

    Item {
      id: fsKeys
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (e) { root.keyPress(e) }
      Keys.onReleased: function (e) { root.keyRelease(e) }

      // Layer-shell hands the surface keyboard focus, but Qt still needs an
      // item inside it holding active focus before Keys handlers fire.
      onVisibleChanged: if (visible) Qt.callLater(fsKeys.forceActiveFocus)

      FullscreenTimer {
        anchors.fill: parent
        panelRoot: root
      }
    }
  }
}
