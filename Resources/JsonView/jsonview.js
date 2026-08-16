/* Kevit++ JSON viewer host.
 *
 * Bridge: window.snppSetJson({json: "<raw text>"}) renders the tree;
 * snppSetTheme('light'|'dark') switches the palette. Posts jsonReady once
 * booted and jsonError when the document doesn't parse (the error is also
 * rendered in-page, so the pane stays informative without the message).
 */
(function () {
  "use strict";

  var content = null;
  var searchBox = null;
  var matchCount = null;
  var breadcrumb = null;
  var matches = [];
  var matchIndex = -1;
  var lastText = "";

  function post(name, body) {
    try { webkit.messageHandlers[name].postMessage(body); } catch (e) {}
  }

  function esc(s) {
    return String(s)
      .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function typeOf(value) {
    if (value === null) return "null";
    if (Array.isArray(value)) return "array";
    return typeof value;
  }

  function describeInline(value, budget) {
    var t = typeOf(value);
    if (t === "string") return JSON.stringify(truncate(value, budget));
    if (t === "number" || t === "boolean") return String(value);
    if (t === "null") return "null";
    if (t === "array") return "Array(" + value.length + ")";
    var keys = Object.keys(value);
    return "Object(" + keys.length + ")";
  }

  function truncate(s, n) {
    return s.length > n ? s.slice(0, n - 1) + "…" : s;
  }

  function typeName(value) {
    var t = typeOf(value);
    return t === "array" ? "array" : t;
  }

  // Row builder. Rows carry `data-path` so the breadcrumb can echo the full
  // path of whatever the user hovers or selects.
  function buildNode(key, value, path, depth) {
    var t = typeOf(value);
    var row = document.createElement("div");
    row.className = "jrow";
    row.dataset.path = path;

    var expander = document.createElement("span");
    expander.className = "expander" + (t === "object" || t === "array" ? "" : " leaf");
    row.appendChild(expander);

    if (key !== null) {
      var keySpan = document.createElement("span");
      keySpan.className = "t-key";
      keySpan.textContent = JSON.stringify(key);
      row.appendChild(keySpan);
      row.appendChild(document.createTextNode(": "));
    }

    var loc = document.createElement("span");
    loc.className = "loc";
    row.appendChild(loc);

    var children = null;

    if (t === "object" || t === "array") {
      var isObject = t === "object";
      var entries = isObject
        ? Object.keys(value).map(function (k) { return [k, value[k]]; })
        : value.map(function (v, i) { return [i, v]; });

      var open = depth < 2; // deep structures start collapsed
      var openCount = 0;

      var bracketOpen = document.createTextNode(isObject ? "{" : "[");
      loc.appendChild(bracketOpen);
      var meta = document.createElement("span");
      meta.className = "t-meta";
      meta.textContent = entries.length + (open ? "" : " … " + (isObject ? "}" : "]"));
      row.appendChild(meta);

      children = document.createElement("div");
      children.className = "children" + (open ? "" : " hidden");
      entries.forEach(function (pair) {
        var childKey = isObject ? pair[0] : null;
        var childPath = isObject
          ? path + "." + JSON.stringify(pair[0]).slice(1, -1)
          : path + "[" + pair[0] + "]";
        children.appendChild(buildNode(childKey, pair[1], childPath, depth + 1));
      });
      var closeRow = document.createElement("div");
      closeRow.className = "jrow";
      closeRow.style.paddingLeft = (14 + depth * 16) + "px";
      closeRow.appendChild(document.createTextNode(isObject ? "}" : "]"));
      children.appendChild(closeRow);

      var state = { open: open };
      function toggle() {
        state.open = !state.open;
        children.classList.toggle("hidden", !state.open);
        meta.textContent = entries.length + (state.open ? "" : " … " + (isObject ? "}" : "]"));
      }
      expander.textContent = open ? "▾" : "▸";
      expander.addEventListener("click", function (e) {
        e.stopPropagation();
        toggle();
        expander.textContent = state.open ? "▾" : "▸";
      });
      row.addEventListener("dblclick", toggle);
    } else {
      var valueClass = t === "string" ? "t-str" : t === "number" ? "t-num" : t === "boolean" ? "t-bool" : "t-null";
      var valueSpan = document.createElement("span");
      valueSpan.className = valueClass;
      valueSpan.textContent = t === "string" ? JSON.stringify(truncate(value, 300)) : String(value);
      loc.appendChild(valueSpan);
      var badge = document.createElement("span");
      badge.className = "badge";
      badge.textContent = typeName(value);
      row.appendChild(badge);
      openCount = 1;
    }

    row.addEventListener("mousemove", function () {
      breadcrumb.textContent = path;
    });
    row.addEventListener("click", function () {
      document.querySelectorAll(".jrow.selected").forEach(function (el) {
        el.classList.remove("selected");
      });
      row.classList.add("selected");
      breadcrumb.textContent = path;
    });

    if (children) {
      var wrapper = document.createElement("div");
      wrapper.appendChild(row);
      wrapper.appendChild(children);
      return wrapper;
    }
    return row;
  }

  function render(text) {
    lastText = text;
    matches = [];
    matchIndex = -1;
    updateMatchUI();
    content.innerHTML = "";
    breadcrumb.textContent = "";
    var value;
    try {
      value = JSON.parse(text);
    } catch (err) {
      content.innerHTML =
        '<div class="error-panel"><div class="glyph">⚠</div>' +
        "<h2>Invalid JSON</h2>" +
        "<pre>" + esc(String(err && err.message ? err.message : err)) + "</pre></div>";
      post("jsonError", String(err));
      return;
    }
    content.appendChild(buildNode(null, value, "$", 0));
    post("jsonResult", "ok");
  }

  // --- Search: highlight matches, reveal them, jump between hits.

  function applySearch(query) {
    if (!query) {
      render(lastText);
      return;
    }
    // Re-render then wrap matches (keys and scalar values) in <mark>.
    render(lastText);
    var rx;
    try {
      rx = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
    } catch (e) {
      return;
    }
    matches = [];
    var targets = content.querySelectorAll(".t-key, .t-str, .t-num, .t-bool");
    targets.forEach(function (el) {
      var text = el.textContent;
      if (!rx.test(text)) return;
      rx.lastIndex = 0;
      el.innerHTML = esc(text).replace(rx, function (m) { return "<mark>" + m + "</mark>"; });
      // Reveal: unhide ancestor containers.
      var p = el.parentElement;
      while (p && p !== content) {
        if (p.classList && p.classList.contains("children")) p.classList.remove("hidden");
        p = p.parentElement;
      }
      matches.push(el);
    });
    matchIndex = -1;
    updateMatchUI();
  }

  function updateMatchUI() {
    matchCount.textContent = matches.length
      ? (matchIndex >= 0 ? (matchIndex + 1) + " / " + matches.length : matches.length + " matches")
      : "0 matches";
  }

  function jump(delta) {
    if (!matches.length) return;
    matchIndex = (matchIndex + delta + matches.length) % matches.length;
    matches[matchIndex].scrollIntoView({ block: "center", behavior: "smooth" });
    updateMatchUI();
  }

  // --- Expand / collapse helpers

  function setAllOpen(open) {
    content.querySelectorAll(".children").forEach(function (el) {
      el.classList.toggle("hidden", !open);
    });
    content.querySelectorAll(".expander:not(.leaf)").forEach(function (el) {
      el.textContent = open ? "▾" : "▸";
    });
  }

  window.snppSetJson = function (payload) {
    var text = payload && payload.json ? JSON.parse(payload.json) : "";
    render(text);
    return "ok";
  };

  window.snppSetTheme = function (theme) {
    if (theme === "light" || theme === "dark") {
      document.documentElement.dataset.theme = theme;
    } else {
      delete document.documentElement.dataset.theme;
    }
  };

  window.snppIsReady = function () { return true; };

  function boot() {
    content = document.getElementById("content");
    searchBox = document.getElementById("search");
    matchCount = document.getElementById("match-count");
    breadcrumb = document.getElementById("breadcrumb");

    var debounce = null;
    searchBox.addEventListener("input", function () {
      clearTimeout(debounce);
      debounce = setTimeout(function () { applySearch(searchBox.value); }, 160);
    });
    searchBox.addEventListener("keydown", function (e) {
      if (e.key === "Enter") { e.preventDefault(); jump(e.shiftKey ? -1 : 1); }
    });
    document.getElementById("next-match").addEventListener("click", function () { jump(1); });
    document.getElementById("prev-match").addEventListener("click", function () { jump(-1); });
    document.getElementById("expand-all").addEventListener("click", function () { setAllOpen(true); });
    document.getElementById("collapse-all").addEventListener("click", function () { setAllOpen(false); });

    post("jsonReady", "ok");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
