import React, { useCallback, useEffect, useRef, useState } from "react";
import { Excalidraw, serializeAsJSON, exportToBlob, exportToSvg } from "@excalidraw/excalidraw";

function parseScene(raw) {
  if (!raw) return null;
  try {
    const data = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!data || data.type !== "excalidraw") return null;
    return data;
  } catch {
    return null;
  }
}

function toFileJSON(elements, appState, files) {
  return serializeAsJSON(elements, appState, files || {}, "local");
}

function blobToBase64(blob) {
  return blob.arrayBuffer().then((buf) => {
    const bytes = new Uint8Array(buf);
    let binary = "";
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
    }
    return btoa(binary);
  });
}

const RESTORED_APP_STATE_KEYS = [
  "viewBackgroundColor",
  "gridSize",
  "theme",
  "scrollX",
  "scrollY",
  "zoom",
];

// Only copy keys the saved scene actually carries. Writing `undefined` over a key
// Excalidraw depends on (zoom, theme, …) makes it throw on the next render and
// unmount itself — a saved scene without `zoom` used to blank the canvas.
function safeAppState(data, current) {
  const src = data.appState || {};
  const next = { ...(current || {}), isLoading: false };
  for (const key of RESTORED_APP_STATE_KEYS) {
    if (src[key] !== undefined) {
      next[key] = src[key];
    }
  }
  return next;
}

function applyScene(api, data) {
  api.updateScene({
    elements: data.elements || [],
    appState: safeAppState(data, api.getAppState()),
    collaborators: new Map(),
  });
  if (data.files) {
    const blobs = Object.values(data.files).filter(Boolean);
    if (blobs.length && api.addFiles) {
      api.addFiles(blobs);
    }
  }
}

export default function App() {
  const api = useRef(null);
  const [theme, setTheme] = useState(window.__SNPP_THEME__ || "light");

  const postScene = useCallback((elements, appState, files) => {
    const json = toFileJSON(elements, appState, files);
    window.webkit?.messageHandlers?.drawingChanged?.postMessage(json);
  }, []);

  useEffect(() => {
    window.snppSetTheme = (next) => setTheme(next === "dark" ? "dark" : "light");
    window.snppGetScene = () => {
      if (!api.current) return window.__SNPP_SCENE__ || "";
      return toFileJSON(
        api.current.getSceneElements(),
        api.current.getAppState(),
        api.current.getFiles()
      );
    };
    window.snppSetScene = (json) => {
      const data = parseScene(json);
      if (!data || !api.current) {
        window.__SNPP_SCENE__ = json;
        return;
      }
      applyScene(api.current, data);
    };
    window.snppRefresh = () => {
      window.dispatchEvent(new Event("resize"));
      if (!api.current) return;
      if (typeof api.current.refresh === "function") {
        api.current.refresh();
      }
      api.current.updateScene({ appState: { isLoading: false } });
    };
    window.snppExportPNG = async () => {
      if (!api.current) return null;
      const blob = await exportToBlob({
        elements: api.current.getSceneElements(),
        appState: {
          ...api.current.getAppState(),
          exportBackground: true,
          isLoading: false,
        },
        files: api.current.getFiles(),
        mimeType: "image/png",
        exportPadding: 16,
      });
      return blobToBase64(blob);
    };
    window.snppExportSVG = async () => {
      if (!api.current) return null;
      const svg = await exportToSvg({
        elements: api.current.getSceneElements(),
        appState: {
          ...api.current.getAppState(),
          exportBackground: true,
          isLoading: false,
        },
        files: api.current.getFiles(),
        exportPadding: 16,
      });
      return new XMLSerializer().serializeToString(svg);
    };
    return () => {
      delete window.snppSetTheme;
      delete window.snppGetScene;
      delete window.snppSetScene;
      delete window.snppRefresh;
      delete window.snppExportPNG;
      delete window.snppExportSVG;
    };
  }, []);

  return (
    <div style={{ height: "100%", width: "100%" }}>
      <Excalidraw
        excalidrawAPI={(next) => {
          api.current = next;
          const pending = parseScene(window.__SNPP_SCENE__);
          if (pending) {
            applyScene(next, pending);
          }
          requestAnimationFrame(() => {
            next.updateScene({ appState: { isLoading: false } });
            if (typeof next.refresh === "function") next.refresh();
          });
          try {
            window.webkit?.messageHandlers?.drawingReady?.postMessage("ready");
          } catch (e) {}
        }}
        initialData={parseScene(window.__SNPP_SCENE__) || { appState: { isLoading: false } }}
        theme={theme}
        UIOptions={{
          canvasActions: {
            loadScene: false,
            saveToActiveFile: false,
            toggleTheme: false,
          },
        }}
        onChange={(elements, appState, files) => postScene(elements, appState, files)}
      />
    </div>
  );
}
