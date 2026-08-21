"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "../../lib/auth-context";

export default function RegisterPage() {
  const router = useRouter();
  const { isLoggedIn, loginGuest, isLoading } = useAuth();

  const handleRegister = async () => {
    const res = await loginGuest();
    if (res) {
      router.push("/profile");
    }
  };

  return (
    <div className="surface" style={{ maxWidth: 540, margin: "24px auto" }}>
      <div className="surface-head" style={{ marginBottom: 16 }}>
        <div>
          <p className="eyebrow">Quran Platform Auth</p>
          <h2 className="surface-title">Регистрация и устройства</h2>
        </div>
      </div>

      <p className="kpi-desc" style={{ marginBottom: 20 }}>
        В текущей архитектуре MVP используется единая защищенная модель привязки устройств.
        Вам не нужно вводить пароли — устройство регистрируется автоматически через криптографический
        ключ сессии.
      </p>

      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {isLoggedIn ? (
          <div className="alert alert-success">
            Ваше устройство уже зарегистрировано в системе.
          </div>
        ) : (
          <button
            onClick={() => void handleRegister()}
            className="btn btn-primary btn-lg"
            disabled={isLoading}
            style={{ width: "100%" }}
          >
            {isLoading ? "Регистрация устройства..." : "Создать гостевой профиль"}
          </button>
        )}

        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 8 }}>
          <Link href="/login" className="kpi-desc" style={{ color: "var(--primary)" }}>
            Уже есть сессия? Войти
          </Link>
          <Link href="/" className="kpi-desc">
            На главную
          </Link>
        </div>
      </div>
    </div>
  );
}
