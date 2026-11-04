"use client";

import { useEffect, useState } from "react";

type Theme = "system" | "light" | "dark";

const STORAGE_KEY = "mme-display-theme";

export default function ThemeControls() {
  const [theme, setTheme] = useState<Theme>("system");

  useEffect(() => {
    try {
      const saved = window.localStorage.getItem(STORAGE_KEY);
      if (saved === "system" || saved === "light" || saved === "dark") {
        setTheme(saved);
      }
    } catch {
      // Storage may be unavailable; system theme remains usable.
    }
  }, []);

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.theme = theme;

    try {
      window.localStorage.setItem(STORAGE_KEY, theme);
    } catch {
      // Theme still applies for this session when storage is unavailable.
    }
  }, [theme]);

  return (
    <div className="theme-controls" role="group" aria-label="Display theme">
      <span className="theme-label">Theme</span>
      {(["system", "light", "dark"] as const).map((option) => (
        <button
          key={option}
          type="button"
          className="theme-option"
          aria-pressed={theme === option}
          onClick={() => setTheme(option)}
        >
          {option === "system" ? "Auto" : option === "light" ? "Light" : "Dark"}
        </button>
      ))}
    </div>
  );
}
