"use client";

import { useEffect, useState } from "react";
import { Screen, TopBar } from "../../components";
import { Icon } from "../../icons";
import { l } from "../../i18n";
import { usePrototype } from "../../store";
import type { ShareAction, ShareExperience, ShareResult } from "./contracts";
import { mockShareGateway } from "./mockGateway";
import { copyText, openNativeShare } from "./nativeShare";

function eventId() {
  return globalThis.crypto?.randomUUID?.() || `share-${Date.now()}`;
}

export function ShareScreen() {
  const { state, notify } = usePrototype();
  const [experience, setExperience] = useState<ShareExperience | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let active = true;
    mockShareGateway.getExperience({ locale: state.locale, accountMode: state.accountMode }).then((value) => {
      if (active) setExperience(value);
    });
    return () => { active = false; };
  }, [state.accountMode, state.locale]);

  const completeAction = async (action: ShareAction, result: ShareResult) => {
    if (!experience) return;
    await mockShareGateway.trackEvent({
      eventId: eventId(),
      campaignId: experience.campaignId,
      action,
      result,
      occurredAt: new Date().toISOString(),
      accountMode: state.accountMode,
    });
    const message = result === "copied"
      ? l(state.locale, { ru: "Ссылка скопирована", en: "Link copied", ar: "تم نسخ الرابط", tr: "Bağlantı kopyalandı" })
      : result === "shared"
        ? l(state.locale, { ru: "Спасибо, что делитесь IQRO", en: "Thank you for sharing IQRO", ar: "شكرًا لمشاركة إقرأ", tr: "IQRO'yu paylaştığınız için teşekkürler" })
        : result === "unavailable"
          ? l(state.locale, { ru: "Не удалось открыть меню. Скопируйте ссылку ниже.", en: "Sharing is unavailable. Copy the link below.", ar: "المشاركة غير متاحة. انسخ الرابط أدناه.", tr: "Paylaşım kullanılamıyor. Aşağıdaki bağlantıyı kopyalayın." })
          : l(state.locale, { ru: "Отправка отменена", en: "Sharing cancelled", ar: "تم إلغاء المشاركة", tr: "Paylaşım iptal edildi" });
    notify(message);
  };

  const share = async () => {
    if (!experience || busy) return;
    setBusy(true);
    const result = await openNativeShare(experience);
    await completeAction("open-system-share", result);
    setBusy(false);
  };

  const copyLink = async () => {
    if (!experience) return;
    const result = await copyText(experience.referral.shortUrl || experience.downloadUrl);
    await completeAction("copy-link", result);
  };

  const capabilities = [
    { icon: "user" as const, title: l(state.locale, { ru: "Персональные ссылки", en: "Personal links", ar: "الروابط الشخصية", tr: "Kişisel bağlantılar" }), text: l(state.locale, { ru: "Код и короткая ссылка после авторизации", en: "Code and short link after sign-in", ar: "رمز ورابط قصير بعد تسجيل الدخول", tr: "Girişten sonra kod ve kısa bağlantı" }) },
    { icon: "gift" as const, title: l(state.locale, { ru: "Бонусы", en: "Rewards", ar: "المكافآت", tr: "Ödüller" }), text: l(state.locale, { ru: "Начисляются только на сервере", en: "Calculated only by the server", ar: "تُحتسب على الخادم فقط", tr: "Yalnızca sunucuda hesaplanır" }) },
    { icon: "target" as const, title: l(state.locale, { ru: "Аналитика приглашений", en: "Invite analytics", ar: "تحليلات الدعوات", tr: "Davet analitiği" }), text: l(state.locale, { ru: "События уже отделены от интерфейса", en: "Events are already separated from UI", ar: "الأحداث منفصلة عن الواجهة", tr: "Olaylar arayüzden ayrıldı" }) },
    { icon: "refresh" as const, title: l(state.locale, { ru: "Удалённая конфигурация", en: "Remote configuration", ar: "الإعداد عن بُعد", tr: "Uzaktan yapılandırma" }), text: l(state.locale, { ru: "Текст и URL без выпуска новой версии", en: "Copy and URL without a new release", ar: "النص والرابط دون إصدار جديد", tr: "Yeni sürüm olmadan metin ve URL" }) },
  ];

  return (
    <Screen className="share-screen">
      <TopBar back title={l(state.locale, { ru: "Поделиться IQRO", en: "Share IQRO", ar: "شارك إقرأ", tr: "IQRO'yu paylaş" })} subtitle={l(state.locale, { ru: "Настройки", en: "Settings", ar: "الإعدادات", tr: "Ayarlar" })}/>
      <section className="share-hero">
        <span className="share-hero-icon"><Icon name="share" size={30}/></span>
        <span className="eyebrow light">IQRO</span>
        <h1>{l(state.locale, { ru: "Поделитесь спокойным ритмом", en: "Share a calmer rhythm", ar: "شارك إيقاعًا أكثر هدوءًا", tr: "Sakin bir ritmi paylaşın" })}</h1>
        <p>{l(state.locale, { ru: "Сейчас используется системное меню телефона. Персональные приглашения подключатся через отдельный backend-адаптер.", en: "The native share sheet works now. Personal invitations connect later through a dedicated backend adapter.", ar: "تعمل قائمة المشاركة الآن، وستُربط الدعوات الشخصية لاحقًا عبر محول مستقل للخادم.", tr: "Sistem paylaşım menüsü şimdi çalışır; kişisel davetler ayrı bir backend adaptörüyle bağlanır." })}</p>
        <button className="button inverse wide" disabled={!experience || busy} onClick={share}><Icon name="share"/>{busy ? l(state.locale, { ru: "Открываем…", en: "Opening…", ar: "جارٍ الفتح…", tr: "Açılıyor…" }) : l(state.locale, { ru: "Поделиться приложением", en: "Share the app", ar: "مشاركة التطبيق", tr: "Uygulamayı paylaş" })}</button>
      </section>

      <section className="share-link-card">
        <div><span className="detail-label">{l(state.locale, { ru: "Ссылка для скачивания", en: "Download link", ar: "رابط التنزيل", tr: "İndirme bağlantısı" })}</span><span className="adapter-chip">{experience?.source === "remote-config" ? "Remote" : "Local fallback"}</span></div>
        <button onClick={copyLink} disabled={!experience}><span><strong>{experience?.downloadUrl || "…"}</strong><small>{l(state.locale, { ru: "Демо-домен будет заменён перед публикацией", en: "The demo domain is replaced before release", ar: "سيُستبدل النطاق التجريبي قبل النشر", tr: "Demo alan adı yayın öncesi değiştirilecek" })}</small></span><Icon name="copy"/></button>
      </section>

      <section className="share-referral-state">
        <span className="share-referral-icon"><Icon name="link"/></span>
        <span><strong>{l(state.locale, { ru: "Личная ссылка пока не подключена", en: "Personal link is not connected yet", ar: "الرابط الشخصي غير متصل بعد", tr: "Kişisel bağlantı henüz bağlı değil" })}</strong><small>{state.accountMode === "guest" ? l(state.locale, { ru: "В гостевом режиме доступна обычная ссылка", en: "A standard link is available in guest mode", ar: "يتوفر رابط عادي في وضع الضيف", tr: "Misafir modunda standart bağlantı kullanılabilir" }) : l(state.locale, { ru: "Аккаунт готов получить код от backend", en: "The account is ready to receive a backend code", ar: "الحساب جاهز لاستلام رمز من الخادم", tr: "Hesap backend kodunu almaya hazır" })}</small></span>
        <span className="soon-badge">API</span>
      </section>

      <section className="share-capabilities">
        <div className="section-heading"><div><span className="eyebrow">Backend-ready</span><h2>{l(state.locale, { ru: "Можно расширить позже", en: "Ready to extend", ar: "جاهز للتوسعة", tr: "Genişletmeye hazır" })}</h2></div></div>
        <div>{capabilities.map((item) => <article key={item.title}><span><Icon name={item.icon}/></span><div><strong>{item.title}</strong><small>{item.text}</small></div><Icon name="check"/></article>)}</div>
      </section>

      <p className="share-privacy-note"><Icon name="shield" size={17}/>{l(state.locale, { ru: "Клиент не вычисляет бонусы и не помещает личные данные в ссылку. События сохраняются в локальный outbox до подключения аналитики.", en: "The client does not calculate rewards or place personal data in links. Events stay in a local outbox until analytics is connected.", ar: "لا يحسب التطبيق المكافآت ولا يضع بيانات شخصية في الروابط. تُحفظ الأحداث محليًا حتى ربط التحليلات.", tr: "İstemci ödül hesaplamaz ve bağlantılara kişisel veri koymaz. Olaylar analitik bağlanana kadar yerel outbox'ta kalır." })}</p>
    </Screen>
  );
}
