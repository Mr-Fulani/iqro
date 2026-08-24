"use client";

import { useEffect } from "react";

export default function GlobalError({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <html lang="ru">
      <body style={{ margin: 0, background: "#f4f7f6", color: "#17211e", fontFamily: "system-ui, sans-serif" }}>
        <main style={{ width: "min(680px, calc(100% - 32px))", margin: "10vh auto", padding: 32, border: "1px solid #d8e2de", borderRadius: 20, background: "#fff" }}>
          <title>Ошибка загрузки | Quran Platform</title>
          <p style={{ color: "#047857", fontWeight: 800 }}>Quran Platform</p>
          <h1>Не удалось загрузить приложение</h1>
          <p>Произошла временная ошибка. Повторите запрос.</p>
          {error.digest && <p style={{ color: "#64748b", fontSize: 13 }}>ID: {error.digest}</p>}
          <button
            type="button"
            onClick={() => retry()}
            style={{ marginTop: 12, padding: "11px 18px", border: 0, borderRadius: 10, color: "#fff", background: "#047857", fontWeight: 700, cursor: "pointer" }}
          >
            Повторить
          </button>
        </main>
      </body>
    </html>
  );
}
