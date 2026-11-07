// Editable, runnable notebook cells. No dependencies besides Popcorn (the BEAM
// compiled to WebAssembly), which loads on the first run.
//
// Cells are connected like in Livebook: running cell N runs cells 1..N, in a
// fresh VM, the way `elixir file.exs` would. Every cell writes a marker
// ("\x1e<n>\x1e") when it starts, so output lands under the cell that printed it.

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const notebook = $(".notebook");
const runAll = $("#run");
const resetBtn = $("#reset");
const status = $("#status");
const program = $("#program").value;
const file = notebook.dataset.file;
const TIMEOUT_MS = 30_000;
const MARK = "\x1e";

const cells = $$(".cell[data-cell]").map((el, i) => {
  const out = $(".cell-out", el);
  return {
    n: i + 1,
    el,
    line: Number(el.dataset.line),
    pre: $("pre.code", el),
    ta: $("textarea.cell-edit", el),
    btn: $(".cell-run", el),
    out,
    builtHtml: $("pre.code", el).innerHTML,
    builtOut: out.innerHTML,
    src: $("textarea.cell-edit", el).value,
  };
});

// ------------------------------------------------------------ highlighting
// A small Elixir tokenizer. Class names match the ones Makeup emits at build
// time, so edited code looks like the static page.
const KEYWORDS =
  "def|defp|defmodule|defstruct|defprotocol|defimpl|defmacro|defmacrop|defguard|defexception|defdelegate|do|end|fn|case|cond|if|else|unless|with|for|receive|after|try|rescue|catch|raise|reraise|when|and|or|not|in|import|alias|require|use|quote|unquote|true|false|nil";
const TOKENS = [
  ["c", /#.*/],
  ["s", /"""[\s\S]*?(?:"""|$)|"(?:\\.|[^"\\])*"?|'(?:\\.|[^'\\])*'?/],
  ["s", /~[a-zA-Z](?:"(?:\\.|[^"\\])*"|\[[^\]\n]*\]|\{[^}\n]*\}|\([^)\n]*\)|\/[^/\n]*\/|\|[^|\n]*\||<[^>\n]*>)[a-zA-Z]*/],
  ["ss", /:(?:"[^"\n]*"|[a-zA-Z_][\w@]*[?!]?)|\b[a-z_]\w*[?!]?:(?=\s)/],
  ["na", /@[a-z_]\w*/],
  ["nc", /\b[A-Z]\w*(?:\.[A-Z]\w*)*/],
  ["mi", /\b0x[\da-fA-F_]+\b|\b\d[\d_]*(?:\.\d[\d_]*)?(?:e[+-]?\d+)?\b/],
  ["k", new RegExp(`\\b(?:${KEYWORDS})\\b(?![?!:])`)],
  ["o", /\|>|<>|->|<-|=>|\+\+|--|===?|!==?|<=|>=|&&|\|\||::|\\\\|[=+\-*/<>|&^!]/],
  ["p", /[()[\]{},.%]/],
];
const TOKEN_RE = new RegExp(TOKENS.map(([, re]) => `(${re.source})`).join("|"), "g");
const escapeHtml = (s) => s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);

function highlight(src) {
  let html = "";
  let last = 0;
  for (const m of src.matchAll(TOKEN_RE)) {
    html += escapeHtml(src.slice(last, m.index));
    const kind = TOKENS[m.slice(1).findIndex((g) => g !== undefined)][0];
    html += `<span class="${kind}">${escapeHtml(m[0])}</span>`;
    last = m.index + m[0].length;
  }
  return html + escapeHtml(src.slice(last)) + "\n";
}

// ------------------------------------------------------------ editing
const isDirty = () => cells.some((c) => c.ta.value !== c.src);

function fit(cell) {
  cell.ta.style.height = `${cell.pre.offsetHeight}px`;
}

function onEdit(cell) {
  cell.pre.firstElementChild.innerHTML = cell.ta.value ? highlight(cell.ta.value) : "";
  fit(cell);
  resetBtn.hidden = !isDirty();
}

function reset() {
  for (const cell of cells) {
    cell.ta.value = cell.src;
    cell.pre.innerHTML = cell.builtHtml;
    cell.out.innerHTML = cell.builtOut;
    cell.out.classList.toggle("empty", cell.out.textContent.trim() === "");
    cell.out.classList.remove("live", "stale", "quiet");
    fit(cell);
  }
  resetBtn.hidden = true;
  setStatus("");
}

const fitAll = () => cells.forEach(fit);
new ResizeObserver(fitAll).observe(notebook);
fitAll();

// Keep the indentation of the current line; indent one more level after an
// opening `do`, `fn` or `->`.
function newline(ta) {
  const before = ta.value.slice(0, ta.selectionStart);
  const line = before.slice(before.lastIndexOf("\n") + 1);
  let indent = line.match(/^\s*/)[0];
  if (/(\bdo|\bfn|->)\s*$/.test(line)) indent += "  ";
  document.execCommand("insertText", false, "\n" + indent);
}

// ------------------------------------------------------------ autocomplete
let completions = null;
const popup = document.createElement("ul");
popup.className = "ac";
popup.setAttribute("role", "listbox");
popup.hidden = true;
let acItems = [];
let acIndex = 0;
let acCell = null;
let acPrefixLen = 0;
let charWidth = 0;

function loadCompletions() {
  completions ??= fetch("/completions.json").then((r) => r.json()).catch(() => ({ modules: {}, words: [] }));
  return completions;
}

// Modules and functions defined on this page, so `KV.` completes too.
function pageSymbols() {
  const modules = {};
  const words = new Set();
  let current = null;
  for (const line of cells.map((c) => c.ta.value).join("\n").split("\n")) {
    const mod = line.match(/defmodule\s+([A-Z][\w.]*)/);
    if (mod) modules[(current = mod[1])] ??= new Set();
    const def = line.match(/^\s*def(?:macro)?\s+([a-z_]\w*[?!]?)/);
    if (def && current) modules[current].add(def[1]);
    for (const w of line.replace(/#.*$|"(?:\\.|[^"\\])*"/g, "").matchAll(/\b[a-z_]\w*[?!]?/g)) words.add(w[0]);
  }
  return { modules, words };
}

function suggest(before, data) {
  const local = pageSymbols();
  const fn = before.match(/((?:[A-Z]\w*)(?:\.[A-Z]\w*)*|:[a-z_]\w*)\.([a-z_]\w*[?!]?)?$/);
  if (fn) {
    const prefix = fn[2] ?? "";
    const arities = {};
    for (const entry of data.modules[fn[1]] ?? []) {
      const [name, arity] = entry.split("/");
      (arities[name] ??= []).push(arity);
    }
    for (const name of local.modules[fn[1]] ?? []) arities[name] ??= [];
    const items = Object.keys(arities)
      .filter((n) => n.startsWith(prefix) && n !== prefix)
      .sort()
      .map((n) => ({ text: n, hint: arities[n].length ? "/" + arities[n].join(", /") : "" }));
    return { items, prefix };
  }
  const mod = before.match(/(?:^|[^\w.:])([A-Z][\w.]*)$/);
  if (mod) {
    const names = new Set([...Object.keys(data.modules).filter((m) => !m.startsWith(":")), ...Object.keys(local.modules)]);
    const items = [...names].filter((m) => m.startsWith(mod[1]) && m !== mod[1]).sort().map((m) => ({ text: m, hint: "module" }));
    return { items, prefix: mod[1] };
  }
  const word = before.match(/(?:^|[^\w.:@])([a-z_]\w*[?!]?)$/);
  if (word && word[1].length >= 2) {
    const all = new Set([...data.words, ...local.words]);
    const items = [...all].filter((w) => w.startsWith(word[1]) && w !== word[1]).sort().map((w) => ({ text: w, hint: "" }));
    return { items, prefix: word[1] };
  }
  return { items: [], prefix: "" };
}

function closePopup() {
  popup.hidden = true;
  acItems = [];
}

async function updatePopup(cell) {
  const ta = cell.ta;
  if (ta.selectionStart !== ta.selectionEnd) return closePopup();
  const before = ta.value.slice(0, ta.selectionStart);
  const { items, prefix } = suggest(before, await loadCompletions());
  if (!items.length) return closePopup();

  acItems = items.slice(0, 8);
  acIndex = 0;
  acCell = cell;
  acPrefixLen = prefix.length;
  popup.innerHTML = acItems
    .map((it, i) => `<li role="option" data-i="${i}"${i ? "" : ' class="on"'}><b>${escapeHtml(it.text)}</b><span>${escapeHtml(it.hint)}</span></li>`)
    .join("");

  // Monospace font: the caret's position follows from line and column.
  const style = getComputedStyle(ta);
  if (!charWidth) {
    const ctx = document.createElement("canvas").getContext("2d");
    ctx.font = `${style.fontSize} ${style.fontFamily}`;
    charWidth = ctx.measureText("0".repeat(100)).width / 100;
  }
  const lines = before.split("\n");
  const lineHeight = parseFloat(style.lineHeight);
  const col = lines.at(-1).length - prefix.length;
  popup.style.left = `${parseFloat(style.paddingLeft) + col * charWidth - ta.scrollLeft}px`;
  popup.style.top = `${parseFloat(style.paddingTop) + lines.length * lineHeight}px`;
  cell.el.querySelector(".cell-body").appendChild(popup);
  popup.hidden = false;
}

function accept() {
  const item = acItems[acIndex];
  const ta = acCell.ta;
  ta.setSelectionRange(ta.selectionStart - acPrefixLen, ta.selectionStart);
  document.execCommand("insertText", false, item.text);
  closePopup();
}

function moveSelection(delta) {
  acIndex = (acIndex + delta + acItems.length) % acItems.length;
  $$("li", popup).forEach((li, i) => li.classList.toggle("on", i === acIndex));
}

popup.addEventListener("mousedown", (e) => {
  const li = e.target.closest("li");
  if (!li) return;
  e.preventDefault();
  acIndex = Number(li.dataset.i);
  accept();
});

for (const cell of cells) {
  const ta = cell.ta;
  const run = () => execute(cell.n);
  ta.addEventListener("input", (e) => {
    onEdit(cell);
    if (e.inputType?.startsWith("insert") && e.data !== null) updatePopup(cell);
    else if (e.inputType?.startsWith("delete")) updatePopup(cell);
  });
  ta.addEventListener("focus", loadCompletions, { once: true });
  ta.addEventListener("blur", () => setTimeout(closePopup, 100));
  ta.addEventListener("scroll", () => (cell.pre.scrollLeft = ta.scrollLeft));
  ta.addEventListener("keydown", (e) => {
    const open = !popup.hidden && acCell === cell;
    if (open && e.key === "ArrowDown") return e.preventDefault(), moveSelection(1);
    if (open && e.key === "ArrowUp") return e.preventDefault(), moveSelection(-1);
    if (open && (e.key === "Enter" || e.key === "Tab")) return e.preventDefault(), accept();
    if (open && e.key === "Escape") return e.preventDefault(), closePopup();
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter") return e.preventDefault(), run();
    if (e.key === "Tab" && !e.shiftKey) return e.preventDefault(), document.execCommand("insertText", false, "  ");
    if (e.key === "Enter" && !e.shiftKey) return e.preventDefault(), newline(ta);
  });
  cell.btn.addEventListener("click", run);
}

// ------------------------------------------------------------ running
let Popcorn = null;
let vm = null;
let busy = false;
let current = 1;
let inMarker = false;
let markerBuf = "";

// The runtime lives under a versioned path (/popcorn/<hash>/) chosen at build
// time, so a cached old runtime can never be paired with this page.
const loadPopcorn = () => import(`${notebook.dataset.runtime}index.mjs`).then((m) => (Popcorn = m.Popcorn));

function setStatus(text, cls = "") {
  status.textContent = text;
  status.className = `nb-status ${cls}`;
}

function append(text, cls) {
  if (!text) return;
  const cell = cells[Math.min(Math.max(current, 1), cells.length) - 1];
  const code = cell.out.firstElementChild;
  cell.out.classList.remove("empty");
  cell.out.classList.add("live");
  if (cls) {
    const span = document.createElement("span");
    span.className = cls;
    span.textContent = text;
    code.appendChild(span);
  } else {
    code.appendChild(document.createTextNode(text));
  }
}

// Splits streamed output on cell markers, which may straddle chunks.
function route(chunk, cls) {
  let plain = "";
  for (const ch of chunk) {
    if (ch === MARK) {
      if (inMarker) {
        append(plain, cls);
        plain = "";
        current = parseInt(markerBuf, 10) || current;
        markerBuf = "";
      }
      inMarker = !inMarker;
    } else if (inMarker) {
      markerBuf += ch;
    } else {
      plain += ch;
    }
  }
  append(plain, cls);
}

// The unedited page runs the exact program verified at build time. Returns the
// code plus each cell's first line in it, to place compiler diagnostics.
function source(upTo) {
  if (upTo === cells.length && !isDirty()) return { code: program, starts: cells.map((c) => c.line) };
  const starts = [];
  let line = 1;
  const parts = cells.slice(0, upTo).map((c) => {
    starts.push(line);
    line += c.ta.value.split("\n").length + 1; // cells are joined by a blank line
    return `IO.write("\\u001E${c.n}\\u001E"); ${c.ta.value}`;
  });
  return { code: parts.join("\n\n"), starts };
}

function showDiagnostics(diagnostics, starts) {
  for (const d of diagnostics ?? []) {
    let index = 0;
    if (d.line) starts.forEach((start, i) => d.line >= start && (index = i));
    current = index + 1;
    append(`${d.severity}: ${d.message}${d.line ? ` (line ${d.line})` : ""}\n`, "stderr");
  }
}

async function execute(upTo = cells.length) {
  if (busy) return;
  busy = true;
  closePopup();
  notebook.classList.add("running");
  [runAll, ...cells.map((c) => c.btn)].forEach((b) => (b.disabled = true));
  current = 1;
  inMarker = false;
  markerBuf = "";
  for (const cell of cells) {
    const ran = cell.n <= upTo;
    cell.out.classList.remove("live", "quiet");
    cell.out.classList.toggle("stale", !ran);
    if (ran) {
      cell.out.firstElementChild.textContent = "";
      cell.out.classList.add("empty");
    }
  }
  setStatus(Popcorn ? "Starting the BEAM…" : "Loading the BEAM (≈4 MB, first run only)…");

  const what = upTo === cells.length ? "all" : upTo === 1 ? "cell 1" : `cells 1–${upTo}`;
  try {
    navigator.sendBeacon?.("/a", JSON.stringify({ e: "run", p: location.pathname }));
    if (!Popcorn) await loadPopcorn();
    vm?.deinit();
    const started = performance.now();
    vm = await Popcorn.init({
      onStdout: (text) => route(text),
      onStderr: (text) => route(text, "stderr"),
    });
    setStatus(`Running ${what}…`);
    const partial = upTo < cells.length;
    const { code, starts } = source(upTo);
    const result = await vm.call("main", ["run", file, code, partial], { timeoutMs: TIMEOUT_MS });
    if (result.outdated) {
      setStatus("The site was updated. Reload the page to run examples.", "err");
      return;
    }
    showDiagnostics(result.diagnostics, starts);
    // A cell that ran but printed nothing (e.g. it only defines a module) says
    // so, instead of looking like it never ran.
    for (const cell of cells.slice(0, upTo)) {
      if (cell.out.classList.contains("empty")) cell.out.classList.replace("empty", "quiet");
    }
    const ms = Math.round(performance.now() - started);
    if (result.ok) setStatus(`✓ Ran ${what} · ${ms} ms`, "ok");
    else setStatus(`✗ Failed after ${ms} ms (see output)`, "err");
  } catch (error) {
    setStatus(`✗ ${error?.message ?? error}`, "err");
    vm?.deinit();
    vm = null;
  } finally {
    busy = false;
    notebook.classList.remove("running");
    [runAll, ...cells.map((c) => c.btn)].forEach((b) => (b.disabled = false));
  }
}

runAll.addEventListener("click", () => execute());
resetBtn.addEventListener("click", reset);
for (const b of [runAll, ...cells.map((c) => c.btn)]) {
  b.addEventListener("pointerenter", () => Popcorn || loadPopcorn(), { once: true });
}
