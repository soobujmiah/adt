/* ============================================================================
   adt — code copy affordance

   Adds a one-click Copy button to command blocks that opt in with
   `data-copy`. Blocks that are diagrams or prose rather than commands
   (for example the evidence pipeline) are left alone, so nothing that is
   not meant to be pasted ever grows a button.

   Copied text is exactly what the shell should run: `$ ` prompts and
   comment-only lines are dropped, indentation introduced by HTML source
   layout is normalised, and real newlines are preserved.

   No dependencies. Falls back to execCommand for older webviews where
   navigator.clipboard is unavailable.

   Copyright (c) 2026 Sobuj Miah (@soobujmiah) — MIT
   ========================================================================== */
(function () {
  "use strict";

  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "fixed";
    ta.style.left = "-9999px";
    ta.style.top = "0";
    document.body.appendChild(ta);
    ta.select();
    ta.setSelectionRange(0, ta.value.length);
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
    document.body.removeChild(ta);
    return ok;
  }

  /* Commands only: drop `$ ` prompts and comment-only lines, normalise the
     per-line indentation that HTML source layout introduces. */
  function extract(node) {
    return node.textContent
      .replace(/\r\n/g, "\n")
      .replace(/\n[ \t]+/g, "\n")
      .replace(/^\s+|\s+$/g, "")
      .split("\n")
      .map(function (l) { return l.replace(/^\$\s+/, ""); })
      .filter(function (l) { return !/^\s*#/.test(l) && l.trim() !== ""; })
      .join("\n");
  }

  function makeButton(label) {
    var b = document.createElement("button");
    b.type = "button";
    b.className = "cb-copy";
    b.textContent = label.copy;
    b.setAttribute("aria-label", label.copyAria);
    return b;
  }

  function wrap(node, label) {
    if (node.dataset.cb === "1") return;
    node.dataset.cb = "1";

    /* The block can scroll horizontally on narrow screens; put it in the
       keyboard tab order so arrow keys can pan it. */
    node.setAttribute("tabindex", "0");

    var cb = document.createElement("div");
    cb.className = "cb";

    var top = document.createElement("div");
    top.className = "cb-top";

    var dots = document.createElement("span");
    dots.className = "cb-dots";
    dots.setAttribute("aria-hidden", "true");
    dots.innerHTML = "<i></i><i></i><i></i>";

    var lbl = document.createElement("span");
    lbl.className = "cb-lang";
    lbl.textContent = "command";

    var btn = makeButton(label);

    top.appendChild(dots);
    top.appendChild(lbl);
    top.appendChild(btn);

    node.parentNode.insertBefore(cb, node);
    cb.appendChild(top);
    cb.appendChild(node);

    btn.addEventListener("click", function () {
      var text = extract(node);
      if (!text) return;
      var done = function (ok) {
        btn.textContent = ok ? label.copied : label.failed;
        btn.classList.add("copied");
        btn.setAttribute("aria-live", "polite");
        setTimeout(function () {
          btn.textContent = label.copy;
          btn.classList.remove("copied");
          btn.removeAttribute("aria-live");
        }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(
          function () { done(true); },
          function () { done(fallbackCopy(text)); }
        );
      } else {
        done(fallbackCopy(text));
      }
    });
  }

  function init() {
    /* Labels follow the document language so Bengali readers get Bengali
       affordance text; the clipboard payload is unaffected either way. */
    var bn = document.documentElement.getAttribute("lang") === "bn";
    var label = bn
      ? { copy: "কপি", copied: "কপি হয়েছে", failed: "ব্যর্থ", copyAria: "কমান্ড কপি করুন" }
      : { copy: "Copy", copied: "Copied", failed: "Copy failed", copyAria: "Copy commands to clipboard" };

    var blocks = document.querySelectorAll("[data-copy]");
    for (var i = 0; i < blocks.length; i++) wrap(blocks[i], label);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
