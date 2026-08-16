/* Kevit++ Markdown preview host.
 *
 * One renderer serves both the in-app preview pane and the exported
 * standalone HTML, so preview and output are always identical.
 * markdown-it (CommonMark + tables) does the parsing; highlight.js colors
 * fenced code; task lists and GitHub-style alert callouts are small local
 * plugins below.
 *
 * Bridge (mirrors the Excalidraw host conventions):
 *   window.snppSetPreviewContent(jsonMarkdown)  -> "ok"   (scroll-preserving)
 *   window.snppSetPlaceholder(glyph, title, msg) -> "ok"
 *   window.snppRenderMarkdown(jsonMarkdown)      -> html string (body only)
 *   window.snppExportHTML(jsonMarkdown)          -> standalone document html
 *   window.snppSetTheme('light' | 'dark')
 * JS -> Swift messages: markdownReady, markdownError
 */
(function () {
  "use strict";

  var md = null;
  var cachedCSS = "";
  var ready = false;

  function post(name, body) {
    try {
      webkit.messageHandlers[name].postMessage(body);
    } catch (e) {
      /* not running inside WKWebView (e.g. plain browser) */
    }
  }

  // ---------------------------------------------------------------- plugins

  /* - [ ] / - [x] task list items */
  function taskListsPlugin(mdInstance) {
    mdInstance.core.ruler.after("inline", "snpp-task-lists", function (state) {
      var tokens = state.tokens;
      for (var i = 2; i < tokens.length; i++) {
        if (tokens[i].type !== "inline") continue;
        if (tokens[i - 2].type !== "list_item_open") continue;
        var children = tokens[i].children;
        if (!children || !children.length || children[0].type !== "text") continue;
        var m = /^\[([ xX])\][ \t]+/.exec(children[0].content);
        if (!m) continue;
        children[0].content = children[0].content.slice(m[0].length);
        var box = new state.Token("html_inline", "", 0);
        box.content =
          '<input type="checkbox" disabled' +
          (m[1] === " " ? "" : " checked") +
          ">";
        children.unshift(box);
        tokens[i - 2].attrJoin("class", "task-list-item");
        if (m[1] !== " ") tokens[i - 2].attrJoin("class", "done");
      }
    });
  }

  /* > [!NOTE] / [!TIP] / [!IMPORTANT] / [!WARNING] / [!CAUTION] callouts */
  var CALLOUTS = { note: "Note", tip: "Tip", important: "Important", warning: "Warning", caution: "Caution" };

  function alertsPlugin(mdInstance) {
    mdInstance.core.ruler.after("inline", "snpp-alerts", function (state) {
      var tokens = state.tokens;
      for (var i = 0; i + 2 < tokens.length; i++) {
        if (tokens[i].type !== "blockquote_open") continue;
        if (tokens[i + 1].type !== "paragraph_open") continue;
        if (tokens[i + 2].type !== "inline") continue;
        var children = tokens[i + 2].children;
        if (!children || !children.length || children[0].type !== "text") continue;
        var m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\n|$)/i.exec(children[0].content);
        if (!m) continue;
        var kind = m[1].toLowerCase();
        children[0].content = children[0].content.slice(m[0].length).replace(/^\n/, "");
        tokens[i].attrJoin("class", "callout");
        tokens[i].attrJoin("class", kind);
        var title = new state.Token("html_block", "", 0);
        title.content = '<div class="callout-title">' + CALLOUTS[kind] + "</div>";
        tokens.splice(i + 1, 0, title);
        i += 1;
      }
    });
  }

  // ------------------------------------------------------------- renderer

  function escapeHtml(s) {
    return s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function highlightCode(content, lang) {
    if (lang && window.hljs && hljs.getLanguage(lang)) {
      try {
        return hljs.highlight(content, { language: lang, ignoreIllegals: true }).value;
      } catch (e) {
        /* fall through to escaped plain text */
      }
    }
    return escapeHtml(content);
  }

  function createRenderer() {
    var instance = window.markdownit({
      html: false,
      linkify: true,
      typographer: true,
      breaks: false
    });

    instance.use(taskListsPlugin);
    instance.use(alertsPlugin);

    /* Fenced code: highlighted, with a language caption bar. */
    instance.renderer.rules.fence = function (tokens, idx) {
      var token = tokens[idx];
      var lang = (token.info || "").trim().split(/\s+/)[0].toLowerCase();
      var label = lang
        ? '<div class="code-lang"><span>' + escapeHtml(lang) + "</span></div>"
        : "";
      return (
        '<div class="code-block">' +
        label +
        "<pre><code" +
        (lang ? ' class="hljs language-' + escapeHtml(lang) + '"' : ' class="hljs"') +
        ">" +
        highlightCode(token.content, lang) +
        "</code></pre></div>\n"
      );
    };

    /* Links open externally (the preview pane routes them to the browser). */
    var defaultLink =
      instance.renderer.rules.link_open ||
      function (tokens, idx, options, env, self) {
        return self.renderToken(tokens, idx, options);
      };
    instance.renderer.rules.link_open = function (tokens, idx, options, env, self) {
      tokens[idx].attrSet("target", "_blank");
      tokens[idx].attrSet("rel", "noopener noreferrer");
      return defaultLink(tokens, idx, options, env, self);
    };

    /* Lazy-load images. */
    instance.renderer.rules.image = function (tokens, idx, options, env, self) {
      tokens[idx].attrSet("loading", "lazy");
      return self.renderToken(tokens, idx, options);
    };

    return instance;
  }

  /* Wrap tables in a horizontally scrollable container. Applied to a detached
   * node so the same transform serves preview and export. */
  function wrapTables(root) {
    var tables = root.querySelectorAll("table");
    for (var i = 0; i < tables.length; i++) {
      var table = tables[i];
      if (table.parentElement && table.parentElement.classList.contains("table-wrap")) continue;
      var wrap = document.createElement("div");
      wrap.className = "table-wrap";
      table.parentNode.insertBefore(wrap, table);
      wrap.appendChild(table);
    }
  }

  function renderToFragment(markdown) {
    var raw = md.render(markdown || "");
    var root = document.createElement("div");
    root.innerHTML = raw;
    wrapTables(root);
    return root;
  }

  function documentTitle(markdown) {
    var m = /^#\s+(.+)$/m.exec(markdown || "");
    if (m) return m[1].trim().replace(/[*_`[\]]/g, "");
    return "Document";
  }

  // ---------------------------------------------------------------- bridge

  function parsePayload(payload) {
    if (payload && payload.json) return JSON.parse(payload.json);
    return String(payload == null ? "" : payload);
  }

  window.snppRenderMarkdown = function (payload) {
    if (!md) return "";
    return renderToFragment(parsePayload(payload)).innerHTML;
  };

  window.snppSetPreviewContent = function (payload) {
    if (!md) return "not-ready";
    var content = document.getElementById("content");
    var scroller = document.scrollingElement || document.documentElement;
    var prevHeight = scroller.scrollHeight - scroller.clientHeight;
    var ratio = prevHeight > 0 ? scroller.scrollTop / prevHeight : 0;

    content.classList.remove("placeholder");
    content.innerHTML = renderToFragment(parsePayload(payload)).innerHTML;

    var newHeight = scroller.scrollHeight - scroller.clientHeight;
    scroller.scrollTop = ratio * newHeight;
    return "ok";
  };

  window.snppSetPlaceholder = function (glyph, title, message) {
    var content = document.getElementById("content");
    content.classList.add("placeholder");
    content.innerHTML =
      '<div class="placeholder-glyph">' + escapeHtml(String(glyph || "")) + "</div>" +
      "<h2>" + escapeHtml(String(title || "")) + "</h2>" +
      "<p>" + escapeHtml(String(message || "")) + "</p>";
    return "ok";
  };

  window.snppExportHTML = function (payload) {
    if (!md) return "";
    var markdown = parsePayload(payload);
    var title = documentTitle(markdown);
    var bodyHTML = renderToFragment(markdown).innerHTML;
    return [
      "<!DOCTYPE html>",
      '<html lang="en">',
      "<head>",
      '<meta charset="utf-8">',
      '<meta name="viewport" content="width=device-width, initial-scale=1">',
      "<title>" + escapeHtml(title) + "</title>",
      "<style>" + cachedCSS + "</style>",
      "</head>",
      "<body>",
      // No newlines inside <main> — the body must match the preview pane byte-for-byte.
      '<main class="markdown-body" id="content">' + bodyHTML + "</main>",
      "</body>",
      "</html>"
    ].join("\n");
  };

  window.snppSetTheme = function (theme) {
    if (theme === "light" || theme === "dark") {
      document.documentElement.dataset.theme = theme;
    } else {
      delete document.documentElement.dataset.theme;
    }
  };

  window.snppRefresh = function () {
    window.dispatchEvent(new Event("resize"));
  };

  // ------------------------------------------------------------------ boot

  function boot() {
    try {
      if (!window.markdownit) throw new Error("markdown-it failed to load");
      md = createRenderer();
      fetch("markdown.css")
        .then(function (r) {
          return r.text();
        })
        .then(function (text) {
          cachedCSS = text;
          ready = true;
          post("markdownReady", "ok");
        })
        .catch(function (err) {
          post("markdownError", "css load failed: " + err);
        });
    } catch (e) {
      post("markdownError", String((e && e.message) || e));
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  window.snppIsReady = function () {
    return ready;
  };
})();
