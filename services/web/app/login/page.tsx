"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { useAuth } from "../../lib/auth-context";

export default function LoginPage() {
  const router = useRouter();
  const { session, identity, isLoggedIn, loginGuest, logout, isLoading, error } = useAuth();
  const [success, setSuccess] = useState<boolean>(false);

  const handleLogin = async () => {
    const res = await loginGuest();
    if (res) {
      setSuccess(true);
      setTimeout(() => {
        router.push("/profile");
      }, 1000);
    }
  };

  return (
    <div className="surface" style={{ maxWidth: 540, margin: "24px auto" }}>
      <div className="surface-head" style={{ marginBottom: 16 }}>
        <div>
          <p className="eyebrow">Quran Platform Auth</p>
          <h2 className="surface-title">Вход в систему</h2>
        </div>
      </div>

      <p className="kpi-desc" style={{ marginBottom: 20 }}>
        В платформе реализована безопасная криптографическая авторизация гостевых сессий
        (Guest Bootstrap с ротацией Refresh Token). Персональные данные не требуются.
      </p>

      {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}
      {success && <div className="alert alert-success" style={{ marginBottom: 16 }}>Вход успешно выполнен! Перенаправление в профиль...</div>}

      {isLoggedIn ? (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div className="alert alert-info">
            Вы уже авторизованы как пользователь <code>{session?.user.id}</code>
          </div>
          <div style={{ display: "flex", gap: 10 }}>
            <Link href="/profile" className="btn btn-primary" style={{ flex: 1 }}>
              В личный кабинет
            </Link>
            <button onClick={() => void logout()} className="btn btn-secondary">
              Выйти
            </button>
          </div>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <button
            onClick={() => void handleLogin()}
            className="btn btn-primary btn-lg"
            disabled={isLoading}
            style={{ width: "100%" }}
          >
            {isLoading ? "Подключение к API..." : "Войти как гость"}
          </button>

          <div
            style={{
              padding: 14,
              background: "var(--bg-subtle)",
              borderRadius: "var(--radius-md)",
              fontSize: 13,
            }}
          >
            <p style={{ fontWeight: 600, marginBottom: 4 }}>Идентификатор установки:</p>
            <code style={{ fontSize: 12, wordBreak: "break-all" }}>
              {identity.installation_id || "Генерируется автоматически"}
            </code>
          </div>

          <div style={{ textAlign: "center", marginTop: 8 }}>
            <Link href="/" className="kpi-desc" style={{ color: "var(--primary)" }}>
              ← Вернуться на главную
            </Link>
          </div>
        </div>
      )}
    </div>
  );
}
