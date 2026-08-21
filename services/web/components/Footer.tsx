import Link from "next/link";

export function Footer() {
  return (
    <footer className="app-footer">
      <div className="footer-content">
        <div className="footer-brand">
          <span className="brand-mark sm">Q</span>
          <p>
            <strong>Quran Platform</strong> — многоклиентская платформа для чтения Мусхафа,
            прослушивания чтецов, расчёта времени намаза и персональной синхронизации.
          </p>
        </div>

        <div className="footer-links">
          <div className="footer-column">
            <h4>Разделы</h4>
            <Link href="/quran">Коран и Мусхаф</Link>
            <Link href="/audio">Каталог чтецов</Link>
            <Link href="/prayer">Время намаза</Link>
            <Link href="/profile">Синхронизация и закладки</Link>
          </div>

          <div className="footer-column">
            <h4>Разработчикам</h4>
            <a href="http://localhost:8000/api/docs" target="_blank" rel="noreferrer">
              Swagger UI
            </a>
            <a href="http://localhost:8000/api/schema" target="_blank" rel="noreferrer">
              OpenAPI Schema
            </a>
            <Link href="/login">Управление сессией</Link>
          </div>
        </div>
      </div>

      <div className="footer-bottom">
        <p>© 2026 Quran Platform. Издание Мадинского Мусхафа (Хафс ‘ан ‘Асым).</p>
      </div>
    </footer>
  );
}
