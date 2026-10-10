.pragma library

// Facelet simulator for NxN cubes, used to draw the scramble preview.
//
// Hand-written strip cycles ("an R turn sends U's right column to B's left
// column, reversed") are where cube code goes wrong: there are six faces, four
// strips each, and every one of the twenty-four is its own chance to flip an
// index. So nothing here knows about strips. A sticker is a point in space with
// an outward normal, a turn is a rotation of both, and the face/row/column a
// sticker lands on is read back off its normal and position only when it is
// time to draw. One rotation rule covers all eighteen move types, and getting
// that single rule right is the whole correctness burden.
//
// Coordinates are doubled and centered: a cell at index i along an axis sits at
// 2i - (n-1), so the cube is symmetric about 0 and every center stays an exact
// integer for even n as well as odd. That keeps the rotation integer-only --
// no floating point, so no accumulated drift over a 100-move 7x7 scramble.

// Face order is the Singmaster/kociemba convention, U R F D L B. Index into
// this for a sticker's color.
var FACES = ["U", "R", "F", "D", "L", "B"]

// Which axis each face's normal lies on (x=0, y=1, z=2), and which end of it.
// +x is R, +y is U, +z is F.
var FACE_AXIS = { U: 1, R: 0, F: 2, D: 1, L: 0, B: 2 }
var FACE_SIGN = { U: 1, R: 1, F: 1, D: -1, L: -1, B: -1 }

var MOVE_RE = /^(\d*)([URFDLB])(w?)('|2|’)?$/

// Clockwise rotation about the +axis `a`, applied to a 3-vector in place.
//
// For the cyclic axis pair (p, q) = (a+1, a+2) the map is (p, q) -> (q, -p).
// Check it against the three faces: R (a=x, so p=y, q=z) sends +y to -z, which
// is U going to B; U (a=y, p=z, q=x) sends +z to -x, F going to L; F (a=z, p=x,
// q=y) sends +y to +x, U going to R. All three match a real cube, and the one
// rule serves all three axes.
function spin(v, a) {
  var p = (a + 1) % 3
  var q = (a + 2) % 3
  var vp = v[p]
  v[p] = v[q]
  v[q] = -vp
}

function spinTimes(v, a, times) {
  for (var i = 0; i < times; i++) spin(v, a)
}

// A solved cube as a flat list of stickers. Every cell on each of the six outer
// layers contributes one sticker, so an n-cube yields 6n^2 of them.
function solved(n) {
  var stickers = []
  var off = n - 1
  for (var f = 0; f < 6; f++) {
    var face = FACES[f]
    var axis = FACE_AXIS[face]
    var sign = FACE_SIGN[face]
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        var pos = [0, 0, 0]
        var nrm = [0, 0, 0]
        nrm[axis] = sign
        // The two axes other than the normal's are the in-face ones; the normal
        // axis is pinned to whichever end of the cube this face is.
        pos[axis] = sign * off
        var p = (axis + 1) % 3
        var q = (axis + 2) % 3
        pos[p] = 2 * i - off
        pos[q] = 2 * j - off
        stickers.push({ p: pos, n: nrm, c: f })
      }
    }
  }
  return { n: n, s: stickers }
}

function parseMove(token, n) {
  var m = MOVE_RE.exec(token)
  if (!m) return null
  var face = m[2]
  var depth = m[3] === "w" ? (m[1] ? parseInt(m[1], 10) : 2) : (m[1] ? parseInt(m[1], 10) : 1)
  if (depth < 1) return null
  // A turn deeper than half the cube is the same as a shallower turn of the
  // opposite face plus a whole-cube rotation; rather than guess which the
  // caller meant, clamp so a malformed scramble still draws something sane.
  if (depth > n) depth = n
  var suffix = m[4] === "’" ? "'" : m[4]
  var turns = suffix === "2" ? 2 : (suffix === "'" ? 3 : 1)
  return { face: face, depth: depth, turns: turns }
}

// Apply one move. `turns` counts quarter turns clockwise as seen from outside
// the face, which for a negative-end face (D, L, B) is counterclockwise about
// the positive axis -- hence the 4 - turns.
function applyMove(cube, move) {
  var n = cube.n
  var off = n - 1
  var axis = FACE_AXIS[move.face]
  var sign = FACE_SIGN[move.face]
  var spins = sign > 0 ? move.turns : (4 - move.turns) % 4
  if (spins === 0) return

  // Outermost layer sits at coordinate sign*off; each layer inward steps 2
  // toward the middle. A depth-d move takes layers 0..d-1.
  var inner = sign * (off - 2 * (move.depth - 1))
  for (var i = 0; i < cube.s.length; i++) {
    var st = cube.s[i]
    var coord = st.p[axis]
    // `sign * coord >= sign * inner` in both directions, written out to keep
    // the comparison obvious.
    var inLayer = sign > 0 ? (coord >= inner) : (coord <= inner)
    if (!inLayer) continue
    spinTimes(st.p, axis, spins)
    spinTimes(st.n, axis, spins)
  }
}

function applyScramble(cube, scramble) {
  var tokens = String(scramble || "").split(/\s+/)
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] === "") continue
    var mv = parseMove(tokens[i], cube.n)
    if (mv) applyMove(cube, mv)
  }
  return cube
}

// Read a sticker's face back off its normal.
function faceOf(nrm) {
  for (var f = 0; f < 6; f++) {
    var face = FACES[f]
    if (nrm[FACE_AXIS[face]] === FACE_SIGN[face]) return face
  }
  return null
}

// Where a sticker sits within its face, as (row, col) with row 0 at the top and
// col 0 at the left of the standard unfolded net:
//
//       U
//   L   F   R   B
//       D
//
// U is drawn above F, so U's top row is its back edge; D is drawn below F, so
// D's top row is its front edge. The side faces all have +y at the top, and
// their columns run left to right as you walk around the cube: L has B on its
// left, R has F on its left, B has R on its left.
function cellOf(n, face, pos) {
  var off = n - 1
  var x = (pos[0] + off) / 2
  var y = (pos[1] + off) / 2
  var z = (pos[2] + off) / 2
  switch (face) {
    case "U": return { r: z, c: x }
    case "D": return { r: off - z, c: x }
    case "F": return { r: off - y, c: x }
    case "B": return { r: off - y, c: off - x }
    case "R": return { r: off - y, c: off - z }
    case "L": return { r: off - y, c: z }
  }
  return null
}

// Flatten to { U: [[colorIndex...]...], R: ..., ... } for the renderer.
function facelets(cube) {
  var n = cube.n
  var out = {}
  for (var f = 0; f < 6; f++) {
    var rows = []
    for (var r = 0; r < n; r++) {
      var row = []
      for (var c = 0; c < n; c++) row.push(-1)
      rows.push(row)
    }
    out[FACES[f]] = rows
  }
  for (var i = 0; i < cube.s.length; i++) {
    var st = cube.s[i]
    var face = faceOf(st.n)
    if (face === null) continue
    var cell = cellOf(n, face, st.p)
    out[face][cell.r][cell.c] = st.c
  }
  return out
}

// The one call the panel makes: scramble string in, net to draw out.
function netFor(n, scramble) {
  return facelets(applyScramble(solved(n), scramble))
}
