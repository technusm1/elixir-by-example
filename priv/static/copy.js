// Copy buttons on code cells and their output. The code button copies what is
// in the cell now, edits included.

const ICON_MS = 1500;

async function copy(btn) {
  const cell = btn.closest(".cell");
  const text =
    btn.dataset.copy === "code"
      ? (cell.querySelector("textarea.cell-edit")?.value ?? cell.querySelector("pre.code").textContent)
      : cell.querySelector(".cell-out").textContent;
  try {
    await navigator.clipboard.writeText(text.replace(/\s+$/, "") + "\n");
    btn.classList.add("done");
    btn.setAttribute("aria-label", "Copied");
    clearTimeout(btn.copyTimer);
    btn.copyTimer = setTimeout(() => {
      btn.classList.remove("done");
      btn.setAttribute("aria-label", btn.title);
    }, ICON_MS);
  } catch {
    btn.title = "Copy failed: select the text and copy it by hand";
  }
}

document.addEventListener("click", (e) => {
  const btn = e.target.closest("button.copy");
  if (btn) copy(btn);
});
