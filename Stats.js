.pragma library

// Times, averages, and the session file format.
//
// The averaging follows WCA regulation 9f: for 5 to 12 solves drop the single
// best and single worst and mean the rest; for 13 and up drop the best and
// worst 5% (rounded up) from each end. A mean of 3 is a plain mean with no
// trim. DNFs are not skipped -- they sort to the worst end and get trimmed like
// any other time, which is why one DNF in an Ao5 is survivable and two are not.
// Getting that wrong flatters the user, so it is tested rather than assumed.

var PENALTY_NONE = ""
var PENALTY_PLUS2 = "+2"
var PENALTY_DNF = "DNF"

// A +2 is two seconds added to the recorded time; a DNF has no time at all.
// `null` means "no finite result", and every consumer has to handle it.
function effective(solve) {
  if (!solve) return null
  if (solve.penalty === PENALTY_DNF) return null
  return solve.ms + (solve.penalty === PENALTY_PLUS2 ? 2000 : 0)
}

function isDnf(solve) {
  return !!solve && solve.penalty === PENALTY_DNF
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

// Centiseconds or milliseconds, minutes only once they are needed. Truncating
// rather than rounding is deliberate: a 9.999 shown as "10.00" reads as a
// time the solver did not have.
function fmt(ms, decimals) {
  if (ms === null || ms === undefined || !isFinite(ms)) return "—"
  var d = decimals === 3 ? 3 : 2
  var total = Math.floor(ms)
  var minutes = Math.floor(total / 60000)
  var rest = total - minutes * 60000
  var seconds = Math.floor(rest / 1000)
  var frac = rest - seconds * 1000
  var fracStr = d === 3 ? (frac < 10 ? "00" + frac : (frac < 100 ? "0" + frac : String(frac)))
                        : pad2(Math.floor(frac / 10))
  if (minutes > 0) return minutes + ":" + pad2(seconds) + "." + fracStr
  return seconds + "." + fracStr
}

// What goes in the times list: the time as it counts, with a marker saying why
// it differs from the raw one.
function fmtSolve(solve, decimals) {
  if (!solve) return "—"
  if (isDnf(solve)) return "DNF"
  var s = fmt(effective(solve), decimals)
  return solve.penalty === PENALTY_PLUS2 ? s + "+" : s
}

function trimCount(n) {
  if (n < 5) return 0
  if (n < 13) return 1
  return Math.ceil(n * 0.05)
}

// Average of the n solves ending at `end` (inclusive). Returns a number, or
// null for a DNF average, or undefined when there aren't n solves to use.
function averageAt(solves, n, end) {
  if (!solves || n < 1 || end < n - 1 || end >= solves.length) return undefined
  var vals = []
  for (var i = end - n + 1; i <= end; i++) {
    var e = effective(solves[i])
    vals.push(e === null ? Infinity : e)
  }
  vals.sort(function (a, b) { return a - b })
  var t = trimCount(n)
  var kept = vals.slice(t, n - t)
  var sum = 0
  for (var j = 0; j < kept.length; j++) {
    if (!isFinite(kept[j])) return null
    sum += kept[j]
  }
  return sum / kept.length
}

// The current rolling average, i.e. the one ending on the most recent solve.
function currentAverage(solves, n) {
  if (!solves || solves.length < n) return undefined
  return averageAt(solves, n, solves.length - 1)
}

// Best average over the whole session, with the index it ends on so the times
// list can mark it.
function bestAverage(solves, n) {
  if (!solves || solves.length < n) return { ms: undefined, end: -1 }
  var best = undefined
  var at = -1
  for (var end = n - 1; end < solves.length; end++) {
    var a = averageAt(solves, n, end)
    if (a === null || a === undefined) continue
    if (best === undefined || a < best) { best = a; at = end }
  }
  return { ms: best, end: at }
}

function finiteTimes(solves) {
  var out = []
  for (var i = 0; i < (solves || []).length; i++) {
    var e = effective(solves[i])
    if (e !== null) out.push(e)
  }
  return out
}

function best(solves) {
  var t = finiteTimes(solves)
  if (t.length === 0) return undefined
  var m = t[0]
  for (var i = 1; i < t.length; i++) if (t[i] < m) m = t[i]
  return m
}

function worst(solves) {
  var t = finiteTimes(solves)
  if (t.length === 0) return undefined
  var m = t[0]
  for (var i = 1; i < t.length; i++) if (t[i] > m) m = t[i]
  return m
}

function mean(solves) {
  var t = finiteTimes(solves)
  if (t.length === 0) return undefined
  var sum = 0
  for (var i = 0; i < t.length; i++) sum += t[i]
  return sum / t.length
}

// Population standard deviation over the solves that have a time.
function stdev(solves) {
  var t = finiteTimes(solves)
  if (t.length < 2) return undefined
  var m = mean(solves)
  var acc = 0
  for (var i = 0; i < t.length; i++) acc += (t[i] - m) * (t[i] - m)
  return Math.sqrt(acc / t.length)
}

function dnfCount(solves) {
  var c = 0
  for (var i = 0; i < (solves || []).length; i++) if (isDnf(solves[i])) c++
  return c
}

function bestIndex(solves) {
  var b = best(solves)
  if (b === undefined) return -1
  for (var i = 0; i < solves.length; i++) if (effective(solves[i]) === b) return i
  return -1
}

// ---------------------------------------------------------------- pace
//
// "What do I need on this solve to beat my best Ao5?" -- the number a solver
// actually wants mid-session, which cstimer leaves them to work out.
//
// The average is monotonic in the pending time, so a binary search finds the
// threshold without needing a closed form for each trim rule. Returning the
// two edge cases explicitly matters: if even an instant solve misses the
// target the answer is "impossible", and if even a DNF clears it the answer is
// "already safe", and those read very differently to a solver.
function neededFor(solves, n, targetMs) {
  if (!solves || targetMs === undefined || targetMs === null) return null
  if (solves.length < n - 1) return null
  var prev = solves.slice(solves.length - (n - 1))

  function avgWith(pendingMs) {
    var trial = prev.concat([{ ms: pendingMs === null ? 0 : pendingMs,
                               penalty: pendingMs === null ? PENALTY_DNF : PENALTY_NONE }])
    return averageAt(trial, n, n - 1)
  }

  var withDnf = avgWith(null)
  if (withDnf !== null && withDnf !== undefined && withDnf < targetMs) {
    return { ms: null, safe: true }
  }
  var floor = avgWith(0)
  if (floor === null || floor === undefined || floor >= targetMs) return { ms: null, safe: false }

  var lo = 0
  var hi = 600000
  for (var i = 0; i < 32; i++) {
    var mid = Math.floor((lo + hi) / 2)
    var a = avgWith(mid)
    if (a !== null && a !== undefined && a < targetMs) lo = mid
    else hi = mid
  }
  return { ms: lo, safe: false }
}

// ---------------------------------------------------------------- histogram

// Equal-width buckets over the session's finite times, for the distribution
// bars. Returns [] rather than a single degenerate bucket when there is
// nothing to show a shape with.
function histogram(solves, buckets) {
  var t = finiteTimes(solves)
  if (t.length < 2) return []
  var lo = Math.min.apply(null, t)
  var hi = Math.max.apply(null, t)
  if (hi <= lo) return [{ from: lo, to: lo, count: t.length }]
  var b = Math.max(2, buckets || 12)
  var width = (hi - lo) / b
  var out = []
  for (var i = 0; i < b; i++) out.push({ from: lo + i * width, to: lo + (i + 1) * width, count: 0 })
  for (var j = 0; j < t.length; j++) {
    var idx = Math.floor((t[j] - lo) / width)
    if (idx >= b) idx = b - 1
    out[idx].count++
  }
  return out
}

// ---------------------------------------------------------------- records

function makeSolve(ms, scramble, puzzleId, atMs) {
  return { ms: Math.round(ms), penalty: PENALTY_NONE, scramble: scramble || "",
           puzzle: puzzleId || "333", at: atMs || Date.now(), note: "" }
}

function newSession(name, puzzleId) {
  return { name: name || "Session 1", puzzle: puzzleId || "333", solves: [] }
}

function emptyStore() {
  return { version: 1, current: 0, sessions: [newSession("Session 1", "333")] }
}

// Accept anything and hand back something the panel can render. A session file
// is the one thing here the user cannot regenerate, so a partially corrupt one
// is repaired field by field rather than thrown away.
function normalizeStore(raw) {
  var store = emptyStore()
  if (!raw || typeof raw !== "object") return store
  var sessions = []
  var list = Array.isArray(raw.sessions) ? raw.sessions : []
  for (var i = 0; i < list.length; i++) {
    var s = list[i] || {}
    var solves = []
    var sl = Array.isArray(s.solves) ? s.solves : []
    for (var j = 0; j < sl.length; j++) {
      var v = sl[j] || {}
      var ms = Number(v.ms)
      if (!isFinite(ms) || ms < 0) continue
      var pen = v.penalty === PENALTY_PLUS2 || v.penalty === PENALTY_DNF ? v.penalty : PENALTY_NONE
      solves.push({ ms: Math.round(ms), penalty: pen,
                    scramble: typeof v.scramble === "string" ? v.scramble : "",
                    puzzle: typeof v.puzzle === "string" ? v.puzzle : "333",
                    at: isFinite(Number(v.at)) ? Number(v.at) : 0,
                    note: typeof v.note === "string" ? v.note : "" })
    }
    sessions.push({ name: typeof s.name === "string" && s.name ? s.name : "Session " + (i + 1),
                    puzzle: typeof s.puzzle === "string" ? s.puzzle : "333",
                    solves: solves })
  }
  if (sessions.length === 0) sessions = [newSession("Session 1", "333")]
  var cur = Number(raw.current)
  if (!isFinite(cur) || cur < 0 || cur >= sessions.length) cur = 0
  return { version: 1, current: Math.floor(cur), sessions: sessions }
}

function sessionNames(store) {
  var out = []
  for (var i = 0; i < store.sessions.length; i++) {
    out.push(store.sessions[i].name + "  (" + store.sessions[i].solves.length + ")")
  }
  return out
}

function csv(session, decimals) {
  var lines = ["no,time,penalty,result,scramble,note,at"]
  for (var i = 0; i < session.solves.length; i++) {
    var s = session.solves[i]
    var note = String(s.note || "").replace(/"/g, '""')
    var scr = String(s.scramble || "").replace(/"/g, '""').replace(/\n/g, " ")
    lines.push([i + 1, fmt(s.ms, decimals), s.penalty || "", fmtSolve(s, decimals),
                '"' + scr + '"', '"' + note + '"',
                s.at ? new Date(s.at).toISOString() : ""].join(","))
  }
  return lines.join("\n") + "\n"
}

// Relative time for the "solved 4m ago" line.
function ago(ms, nowMs) {
  if (!ms) return ""
  var d = Math.max(0, Math.floor((nowMs - ms) / 1000))
  if (d < 60) return "just now"
  if (d < 3600) return Math.floor(d / 60) + "m ago"
  if (d < 86400) return Math.floor(d / 3600) + "h ago"
  return Math.floor(d / 86400) + "d ago"
}
