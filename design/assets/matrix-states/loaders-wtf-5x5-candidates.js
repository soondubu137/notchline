// Notchline 5x5 state matrices - Input needed / Completed candidates.
// Open https://www.loaders.wtf/ , open DevTools (Cmd-Opt-J), paste this whole
// file into the Console, press Enter, then reload the page.
// Existing loaders of yours that this does not define are kept, renumbered from 101.
//
// Twelve loaders: the two patterns this set replaced, as the yardstick, then
// five Input needed and five Completed candidates. **Step and Quincunx are the
// two that shipped** (2026-09-07, figma-design.md 4.1); the wedge and the bars
// beside them are what they replaced, kept here because the case for the
// change is a comparison.
//
// This file is both the loaders.wtf importer and the generator the frames are
// defined in, so it is the one place to change a curve.
//
// Every candidate obeys the one-scale rule: dimmest cell 0.15, brightest 1.0,
// and never at the floor everywhere at once. All but Quincunx also move only
// whole rows or whole columns; Quincunx is five single cells by construction,
// which is the exception argued in figma-design.md 4.1.
;(function(){
'use strict';

const N = 5, FLOOR = 0.15;

const blank = (v = 0) => Array.from({length: N}, () => Array(N).fill(v));
const clamp = x => Math.min(1, Math.max(0, x));
const q = x => Math.round(clamp(x) * 1000) / 1000;
const fin = fs => fs.map(f => f.map(r => r.map(q)));

const norm = (fs, floor = FLOOR) => {
  let mn = 1, mx = 0;
  fs.forEach(f => f.forEach(r => r.forEach(v => { if (v < mn) mn = v; if (v > mx) mx = v; })));
  if (mx - mn < 1e-9) return fs;
  const k = (1 - floor) / (mx - mn);
  return fs.map(f => f.map(r => r.map(v => floor + (v - mn) * k)));
};

const P = [];
const add = (key, state, name, fps, frames, theory, note, opts = {}) =>
  P.push({key, state, name, fps, frames: fin(opts.raw ? frames : norm(frames)), theory, note});


add('drawn-nl5-in-wedge', 'Input needed', 'Wedge (shipping)', 50, (() => {
  const F = 40, span = 5, depth = 1.3;
  let track = Array.from({length: F}, (_, f) =>
    Math.exp(-(((f / F) * span) % span) / depth));
  const mn = Math.min(...track), mx = Math.max(...track), k = (1 - FLOOR) / (mx - mn);
  track = track.map(v => FLOOR + (v - mn) * k);
  const off = (r, c) => (c * 8 + Math.abs(r - 2) * 6) % F;
  return Array.from({length: F}, (_, t) => {
    const f = blank();
    for (let r = 0; r < N; r++) for (let c = 0; c < N; c++)
      f[r][c] = track[((t - off(r, c)) % F + F) % F];
    return f;
  });
})(), 'incumbent', 'A >-fronted band crossing the grid every 0.8s; every cell reaches full once per loop.', {raw: true});

add('drawn-nl5-done-bars', 'Completed', 'Bars (shipping)', 30, (() => {
  const F = 60;
  const track = Array.from({length: F}, (_, f) =>
    0.32 + 0.68 * (0.5 * (1 + Math.cos(2 * Math.PI * f / F))));
  return Array.from({length: F}, (_, t) => {
    const f = blank(FLOOR);
    for (let r = 0; r < N; r += 2) {
      const o = (r / 2) * 11, v = track[((t - o) % F + F) % F];
      for (let c = 0; c < N; c++) f[r][c] = v;
    }
    return f;
  });
})(), 'incumbent', 'Rows 0/2/4 breathe 0.32 to full, eleven frames apart; 15 of 25 cells reach white every 2s.', {raw: true});


add('drawn-nl5-in-caret', 'Input needed', 'Caret', 30, (() => {
  const F = 30, out = [];
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    // 1-frame edges, 13 lit, 15 dark: a terminal cursor, not a strobe.
    let v = 0;
    if (t < 14) v = t === 0 ? 0.5 : 1;
    else if (t === 14) v = 0.5;
    for (let r = 0; r < N; r++) f[r][2] = FLOOR + (1 - FLOOR) * v;
    out.push(f);
  }
  return out;
})(), 'rhythm, not area', 'Five cells of 25, half the time. Loud because a hard on/off edge in one place is unmissable, and because everyone reads a blinking upright as "type here".');

add('drawn-nl5-in-step', 'Input needed', 'Step', 40, (() => {
  const F = 40, hold = 8, out = [];
  for (let t = 0; t < F; t++) {
    const col = Math.floor(t / hold), prev = (col + N - 1) % N, k = t % hold;
    const f = blank(FLOOR);
    // The column strikes and decays across its own step, and the one just
    // vacated keeps a short tail, so the march has a direction and no column
    // is ever held at full for long.
    const v = Math.exp(-k / 3.4);
    for (let r = 0; r < N; r++) {
      f[r][prev] = FLOOR + (1 - FLOOR) * 0.22 * Math.exp(-k / 3.0);
      f[r][col] = FLOOR + (1 - FLOOR) * v;
    }
    out.push(f);
  }
  return out;
})(), 'the march', "Today's wedge stripped to one column and stepped rather than swept. Same left-to-right insistence, a third of the lit area and no smooth glare front.");

add('drawn-nl5-in-hold', 'Input needed', 'Hold', 30, (() => {
  const F = 48, out = [];
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    const v = 0.62 + 0.38 * (0.5 * (1 + Math.cos(2 * Math.PI * t / F)));
    for (let r = 0; r < N; r++) f[r][2] = FLOOR + (1 - FLOOR) * v;
    out.push(f);
  }
  return out;
})(), 'persistence', 'Almost no motion at all: a bright upright that simply will not go away. Loud the way a lit sign is loud rather than the way a flash is.');

add('drawn-nl5-in-beckon', 'Input needed', 'Beckon', 30, (() => {
  const F = 36, out = [];
  const level = (t, on) => { const d = t - on; return d < 0 || d > 9 ? 0 : Math.exp(-d / 3.2); };
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    const pairs = [[[0, 4], 0], [[1, 3], 4], [[2], 8]];
    for (const [cols, on] of pairs) {
      const v = level(t, on);
      for (const c of cols) for (let r = 0; r < N; r++)
        f[r][c] = Math.max(f[r][c], FLOOR + (1 - FLOOR) * v);
    }
    // The centre never goes fully out, so a live mark always has a lit cell.
    for (let r = 0; r < N; r++) f[r][2] = Math.max(f[r][2], 0.38);
    out.push(f);
  }
  return out;
})(), 'a gesture', 'Three columns closing inward once a beat: a summoning motion rather than a passing one. Nothing else on the surface moves toward its own centre.');

add('drawn-nl5-in-prompt', 'Input needed', 'Prompt', 30, (() => {
  const F = 30, out = [];
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    for (let c = 0; c < N; c++) f[4][c] = 0.42;      // the field
    const on = t < 14 ? 1 : t === 14 ? 0.5 : 0;
    for (let r = 0; r < 4; r++) f[r][2] = Math.max(f[r][2], FLOOR + (1 - FLOOR) * on);
    out.push(f);
  }
  return out;
})(), 'literal', 'Caret plus the line it sits on. The most explicit "there is a field here and it is your turn" the grid can draw.');


add('drawn-nl5-done-rule', 'Completed', 'Rule', 30, (() => {
  const F = 72, out = [];
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    const v = 0.45 + 0.55 * (0.5 * (1 + Math.cos(2 * Math.PI * t / F)));
    for (let c = 0; c < N; c++) f[2][c] = FLOOR + (1 - FLOOR) * v;
    out.push(f);
  }
  return out;
})(), 'one third the area', 'Bars with two of its three rules taken away and the breath slowed to 2.4s. The same level, closed, horizontal reading with 5 cells lit instead of 15.');

add('drawn-nl5-done-cascade', 'Completed', 'Cascade', 30, (() => {
  const F = 90, out = [];
  const bump = (t, on) => { const d = ((t - on) % F + F) % F; return d > 24 ? 0 : 0.5 * (1 - Math.cos(2 * Math.PI * d / 24)); };
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    [[0, 0], [2, 14], [4, 28]].forEach(([r, on]) => {
      const v = bump(t, on);
      for (let c = 0; c < N; c++) f[r][c] = FLOOR + (1 - FLOOR) * Math.max(0.06, v);
    });
    out.push(f);
  }
  return out;
})(), 'spread in time', 'The three rules kept, but taking the crest one at a time with a long rest after. Only one rule is ever near white, so the figure survives and the glare does not.');

add('drawn-nl5-done-settle', 'Completed', 'Settle', 30, (() => {
  const F = 72, out = [];
  const bump = (t, on, w) => { const d = t - on; return d < 0 || d > w ? 0 : 0.5 * (1 - Math.cos(2 * Math.PI * d / w)); };
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    [[0, 0, 1.0], [2, 12, 0.66], [4, 24, 0.40]].forEach(([r, on, top]) => {
      const v = top * bump(t, on, 26);
      for (let c = 0; c < N; c++) f[r][c] = FLOOR + (1 - FLOOR) * Math.max(0.05, v);
    });
    out.push(f);
  }
  return out;
})(), 'coming to rest', 'A crest that falls down the grid and loses height at every step, then a long silence. Asymmetric top-to-bottom, so unlike the wedge it witnesses the seam direction.');

add('drawn-nl5-done-ledge', 'Completed', 'Ledge', 30, (() => {
  const F = 90, out = [];
  for (let t = 0; t < F; t++) {
    const f = blank(FLOOR);
    const v = 0.52 + 0.48 * (0.5 * (1 + Math.cos(2 * Math.PI * t / F)));
    for (let c = 0; c < N; c++) f[4][c] = FLOOR + (1 - FLOOR) * v;
    out.push(f);
  }
  return out;
})(), 'nearly a still', 'One rule resting on the floor of the grid, moving so little you would not catch it moving. The quietest thing that is still not the inactive mark.');

add('drawn-nl5-done-quincunx', 'Completed', 'Quincunx', 30, (() => {
  const F = 72, out = [];
  const breath = (t, mult, phase) => 0.5 * (1 + Math.cos(mult * 2 * Math.PI * t / F - phase));
  // The four satellites are two diagonals in antiphase. Neither ever drops out,
  // so every frame is still a quincunx; only the weight across it shifts.
  const DIAG_A = [[0, 0], [4, 4]], DIAG_B = [[0, 4], [4, 0]];
  for (let t = 0; t < F; t++) {
    const f = blank();
    for (const [r, c] of DIAG_A) f[r][c] = 0.86 * (0.30 + 0.70 * breath(t, 1, 0));
    for (const [r, c] of DIAG_B) f[r][c] = 0.86 * (0.30 + 0.70 * breath(t, 1, Math.PI));
    // The centre runs at twice the rate, so it takes the light between each
    // diagonal and the next: A, centre, B, centre. Four beats, never a pause.
    f[2][2] = 0.42 + 0.58 * breath(t, 2, Math.PI);
    out.push(f);
  }
  return out;
})(), 'the die-five', 'Four points about a centre. The two diagonals trade weight while the centre keeps time between them, so the figure never travels and never holds still either. The one candidate built from single cells rather than whole rows.');


  var cp = {}; try { cp = JSON.parse(localStorage.getItem("custom_patterns_v2") || "{}"); } catch(e) {}
  P.forEach(function(p){ cp[p.key] = {frames:p.frames, description:p.state + " \u00b7 " + p.name, createdAt:Date.now()}; });
  var loaders = P.map(function(p,i){ return {id:i+1, pattern:p.key, gridSize:5, fps:p.fps,
    animStyle:"opacity", animStyleBg:"none", cellShape:"roundedRect", glowMode:"hdr", glowIntensity:70,
    gridColor:"#FFFFFF", inactiveColor:"#141414", bgColor:"#000000", textColor:"#FFFFFF",
    displayText:p.state + " \u00b7 " + p.name}; });
  var prev = {}; try { prev = JSON.parse(localStorage.getItem("gridstral_autosave") || "{}"); } catch(e) {}
  var mine = {}; P.forEach(function(p){ mine[p.key] = 1; });
  var keep = (prev.l || []).filter(function(l){ var k = l.p || l.pattern; return k && !mine[k]; });
  keep.forEach(function(l,i){ l.id = 101 + i; });
  localStorage.setItem("custom_patterns_v2", JSON.stringify(cp));
  localStorage.setItem("gridstral_autosave", JSON.stringify({l: loaders.concat(keep), th:"d", cp: cp}));
  console.log("Imported " + loaders.length + " Notchline 5x5 candidates; kept " + keep.length + " existing loader(s). Reload the page.");
  return "imported " + loaders.length + ", kept " + keep.length;
})()
