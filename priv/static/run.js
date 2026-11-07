// Run buttons. Loads the BEAM (compiled to WebAssembly by Popcorn) only when a
// reader first clicks Run, then evaluates the example in a fresh VM per run so
// each run behaves like `elixir file.exs`: no leftover modules or processes.

const run = document.getElementById("run");
const edit = document.getElementById("edit");
const output = document.getElementById("output");
const source = document.getElementById("source");

const original = source.value;
const builtOutput = output.textContent;
const file = location.pathname.split("/").pop() + ".exs";
const TIMEOUT_MS = 30_000;

let PopcornLib = null;
let vm = null;
let busy = false;

function write(text, cls) {
  const span = document.createElement("span");
  if (cls) span.className = cls;
  span.textContent = text;
  output.firstChild.appendChild(span);
}

async function bootVm() {
  if (!PopcornLib) {
    ({ Popcorn: PopcornLib } = await import("/popcorn/index.mjs"));
  }
  return PopcornLib.init({
    onStdout: (text) => write(text),
    onStderr: (text) => write(text, "stderr"),
  });
}

async function execute() {
  if (busy) return;
  busy = true;
  run.disabled = true;
  output.classList.add("live");
  output.firstChild.textContent = "";

  const firstLoad = !PopcornLib;
  run.textContent = firstLoad ? "Loading BEAM…" : "Running…";

  try {
    navigator.sendBeacon?.("/a", JSON.stringify({ e: "run", p: location.pathname }));
    if (vm) vm.deinit();
    const started = performance.now();
    vm = await bootVm();
    if (firstLoad) run.textContent = "Running…";
    const code = source.hidden ? original : source.value;
    const result = await vm.call("main", ["run", file, code], { timeoutMs: TIMEOUT_MS });
    const ms = Math.round(performance.now() - started);
    write(`\n[${result.ok ? "finished" : "failed"} in ${ms} ms, in your browser]`, "meta");
  } catch (error) {
    write(`\n[error: ${error?.message ?? error}]`, "stderr");
    if (vm) vm.deinit();
    vm = null;
  } finally {
    busy = false;
    run.disabled = false;
    run.textContent = "Run";
  }
}

function toggleEdit() {
  const editing = source.hidden;
  source.hidden = !editing;
  edit.textContent = editing ? "Reset" : "Edit";
  if (editing) {
    source.focus();
  } else {
    source.value = original;
    output.classList.remove("live");
    output.firstChild.textContent = builtOutput;
  }
}

run.addEventListener("click", execute);
edit.addEventListener("click", toggleEdit);
source.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") execute();
});

// Warm the module (not the VM) when the reader shows intent.
run.addEventListener("pointerenter", () => {
  if (!PopcornLib) import("/popcorn/index.mjs").then((m) => (PopcornLib = m.Popcorn));
}, { once: true });
