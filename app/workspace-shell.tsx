"use client";

import { useEffect, useState } from "react";

export default function WorkspaceShell({ children }: { children: React.ReactNode }) {
  const [fullScreen, setFullScreen] = useState(false);

  useEffect(() => {
    const sync = () => setFullScreen(Boolean(document.fullscreenElement));
    document.addEventListener("fullscreenchange", sync);
    return () => document.removeEventListener("fullscreenchange", sync);
  }, []);

  async function toggleFullScreen() {
    try {
      if (document.fullscreenElement) {
        await document.exitFullscreen();
      } else {
        await document.documentElement.requestFullscreen();
      }
    } catch {
      // Browser/device policy may deny fullscreen; the workspace remains usable.
    }
  }

  return (
    <>
      <div className="workspace-bar">
        <a className="workspace-brand" href="/" aria-label="Much More Electronics home">
          <span className="workspace-mark">MME</span>
          <span>MUCH MORE ELECTRONICS <small>OPERATING SYSTEM</small></span>
        </a>
        <div className="workspace-tools">
          <span className="workspace-preview"><i /> Preview workspace</span>
          <button type="button" className="workspace-fullscreen" onClick={toggleFullScreen} aria-pressed={fullScreen}>
            <span aria-hidden="true">{fullScreen ? "↙" : "↗"}</span>
            {fullScreen ? "Exit full screen" : "Full screen"}
          </button>
        </div>
      </div>
      <main className="workspace-content">{children}</main>
    </>
  );
}
