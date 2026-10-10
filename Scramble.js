.pragma library

// Scramble generation for every event the timer offers.
//
// These are random-MOVE scrambles, not the random-STATE scrambles the WCA
// requires. The distinction matters and the panel says so rather than letting
// anyone assume otherwise: a random-state scrambler picks a position uniformly
// from the whole group and solves backwards into it, which needs a two-phase
// solver and multi-megabyte lookup tables -- not something to build at shell
// startup. A long enough random-move sequence is close to uniform and is what
// most practice timers ship, but a short one is measurably biased (it cannot
// reach positions further away than its own length), so the lengths below are
// the generous end of convention rather than the minimum that looks random.
//
// Anyone who wants the real thing can point `scrambler` at an external command
// in settings; the panel runs it and uses its output verbatim.

// Which axis a face turns about, so the generator can tell when consecutive
// moves commute. Same letters as Cube.js.
var AXIS_OF = { U: "y", D: "y", R: "x", L: "x", F: "z", B: "z" }

var SUFFIXES = ["", "'", "2"]

// `kind` picks the generator; `size` is the cube order for nxn. `length` is in
// moves (or in (a,b) pairs for Square-1, lines for Megaminx). `preview` marks
// the events whose state Cube.js can draw.
var PUZZLES = [
  { id: "222",    name: "2x2x2",            short: "2x2",   kind: "nxn",   size: 2, length: 11,  preview: true },
  { id: "333",    name: "3x3x3",            short: "3x3",   kind: "nxn",   size: 3, length: 25,  preview: true },
  { id: "444",    name: "4x4x4",            short: "4x4",   kind: "nxn",   size: 4, length: 44,  preview: true },
  { id: "555",    name: "5x5x5",            short: "5x5",   kind: "nxn",   size: 5, length: 60,  preview: true },
  { id: "666",    name: "6x6x6",            short: "6x6",   kind: "nxn",   size: 6, length: 80,  preview: true },
  { id: "777",    name: "7x7x7",            short: "7x7",   kind: "nxn",   size: 7, length: 100, preview: true },
  { id: "333oh",  name: "3x3 One-Handed",   short: "OH",    kind: "nxn",   size: 3, length: 25,  preview: true },
  { id: "333bld", name: "3x3 Blindfolded",  short: "BLD",   kind: "nxn",   size: 3, length: 25,  preview: true, orient: true },
  { id: "pyram",  name: "Pyraminx",         short: "Pyra",  kind: "pyram", length: 11 },
  { id: "skewb",  name: "Skewb",            short: "Skewb", kind: "skewb", length: 11 },
  { id: "mega",   name: "Megaminx",         short: "Mega",  kind: "mega",  length: 7 },
  { id: "sq1",    name: "Square-1",         short: "Sq-1",  kind: "sq1",   length: 13 },
  { id: "clock",  name: "Clock",            short: "Clock", kind: "clock" }
]

function puzzleById(id) {
  for (var i = 0; i < PUZZLES.length; i++) if (PUZZLES[i].id === id) return PUZZLES[i]
  return PUZZLES[1]
}

function puzzleNames() {
  var out = []
  for (var i = 0; i < PUZZLES.length; i++) out.push(PUZZLES[i].name)
  return out
}

function idForName(name) {
  for (var i = 0; i < PUZZLES.length; i++) if (PUZZLES[i].name === name) return PUZZLES[i].id
  return "333"
}

function pick(list, rng) {
  return list[Math.floor(rng() * list.length)]
}

// Depth 1 is the outer layer (R), 2 is a two-layer block (Rw), 3 and deeper
// carry the count (3Rw). This is WCA notation for big cubes.
function moveName(face, depth) {
  if (depth <= 1) return face
  if (depth === 2) return face + "w"
  return String(depth) + face + "w"
}

// Random moves with the two redundancy rules that matter.
//
// Consecutive moves about the same axis commute, so a run of them can be
// reordered freely -- which means if any (face, depth) repeats inside such a
// run, the sequence is equivalent to a shorter one and the scramble is not the
// length it claims. Looking back only one move (the usual shortcut) misses
// "R L R": that reorders to "R R L" and collapses. So the check walks back
// across the whole same-axis run.
function nxnScramble(n, length, rng) {
  var faces = n === 2 ? ["U", "R", "F"] : ["U", "R", "F", "D", "L", "B"]
  var maxDepth = Math.max(1, Math.floor(n / 2))
  var out = []
  var hist = []
  var guard = 0
  while (out.length < length && guard++ < length * 200) {
    var face = pick(faces, rng)
    var depth = 1 + Math.floor(rng() * maxDepth)
    var axis = AXIS_OF[face]
    var clash = false
    for (var i = hist.length - 1; i >= 0 && hist[i].axis === axis; i--) {
      if (hist[i].face === face && hist[i].depth === depth) { clash = true; break }
    }
    if (clash) continue
    out.push(moveName(face, depth) + pick(SUFFIXES, rng))
    hist.push({ axis: axis, face: face, depth: depth })
  }
  return out.join(" ")
}

// Blindfolded scrambles get a random whole-cube orientation on the end, so the
// solver cannot lean on a fixed starting face.
function orientation(rng) {
  var out = []
  var x = pick(["", "x", "x2", "x'"], rng)
  var y = pick(["", "y", "y2", "y'"], rng)
  if (x) out.push(x)
  if (y) out.push(y)
  return out.join(" ")
}

// Four faces, three-fold, so no "2" suffix exists. Tips are the lowercase
// moves at the end; each may be left alone.
function pyramScramble(length, rng) {
  var faces = ["U", "L", "R", "B"]
  var out = []
  var last = ""
  var guard = 0
  while (out.length < length && guard++ < length * 100) {
    var f = pick(faces, rng)
    if (f === last) continue
    last = f
    out.push(f + pick(["", "'"], rng))
  }
  var tips = []
  var tipFaces = ["u", "l", "r", "b"]
  for (var i = 0; i < tipFaces.length; i++) {
    var t = pick(["", tipFaces[i], tipFaces[i] + "'"], rng)
    if (t) tips.push(t)
  }
  return out.concat(tips).join(" ")
}

function skewbScramble(length, rng) {
  var faces = ["U", "L", "R", "B"]
  var out = []
  var last = ""
  var guard = 0
  while (out.length < length && guard++ < length * 100) {
    var f = pick(faces, rng)
    if (f === last) continue
    last = f
    out.push(f + pick(["", "'"], rng))
  }
  return out.join(" ")
}

// WCA Megaminx notation: seven lines, each five R/D pairs then a U turn. The
// ++/-- are double turns of the two outer slices, which is why the face letters
// never vary -- only the direction does.
function megaScramble(lines, rng) {
  var out = []
  for (var l = 0; l < lines; l++) {
    var line = []
    for (var i = 0; i < 5; i++) {
      line.push("R" + pick(["++", "--"], rng))
      line.push("D" + pick(["++", "--"], rng))
    }
    line.push(pick(["U", "U'"], rng))
    out.push(line.join(" "))
  }
  return out.join("\n")
}

// Square-1 as (top, bottom) twelfth-turns separated by a slice. Both halves
// zero would be a no-op pair, so at least one turns.
function sq1Scramble(pairs, rng) {
  var out = []
  for (var i = 0; i < pairs; i++) {
    var a = 0, b = 0
    var guard = 0
    while (a === 0 && b === 0 && guard++ < 50) {
      a = Math.floor(rng() * 12) - 5
      b = Math.floor(rng() * 12) - 5
    }
    out.push("(" + a + "," + b + ")")
  }
  return out.join(" / ")
}

// WCA Clock notation: nine pin positions on the front, the cube flipped, then
// five more on the back.
function clockScramble(rng) {
  function turn() {
    var n = Math.floor(rng() * 7)
    return String(n) + pick(["+", "-"], rng)
  }
  var front = ["UR", "DR", "DL", "UL", "U", "R", "D", "L", "ALL"]
  var back = ["U", "R", "D", "L", "ALL"]
  var out = []
  for (var i = 0; i < front.length; i++) out.push(front[i] + turn())
  out.push("y2")
  for (var j = 0; j < back.length; j++) out.push(back[j] + turn())
  return out.join(" ")
}

// `lengthOverride` is the user's setting; 0 or absent means the event default.
function generate(puzzleId, lengthOverride, rng) {
  var r = rng || Math.random
  var p = puzzleById(puzzleId)
  var len = (lengthOverride && lengthOverride > 0) ? lengthOverride : p.length
  switch (p.kind) {
    case "nxn":
      var s = nxnScramble(p.size, len, r)
      if (p.orient) {
        var o = orientation(r)
        if (o) s += " " + o
      }
      return s
    case "pyram": return pyramScramble(len, r)
    case "skewb": return skewbScramble(len, r)
    case "mega":  return megaScramble(len, r)
    case "sq1":   return sq1Scramble(len, r)
    case "clock": return clockScramble(r)
  }
  return ""
}

// The cube order to draw a preview at, or 0 for events with no preview.
function previewSize(puzzleId) {
  var p = puzzleById(puzzleId)
  return (p.preview && p.kind === "nxn") ? p.size : 0
}

// A whole-cube rotation is not a layer turn, so the preview simulator would
// mis-handle it; strip the orientation suffix before drawing.
function previewScramble(scramble) {
  return String(scramble || "").replace(/\s+[xyz][2']?(?=\s|$)/g, "")
}
