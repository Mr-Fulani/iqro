import type { Locale } from "./i18n";
import type { LegalConfig } from "./legal-config";
import type { LegalDocumentCopy } from "./legal-content";
import { localizedPath } from "./routing";

export type AdditionalLegalCopy = {
  legal: LegalDocumentCopy;
  cookies: LegalDocumentCopy;
  dataRights: LegalDocumentCopy;
  providers: LegalDocumentCopy;
  security: LegalDocumentCopy;
};

const externalLinks = {
  cloudflare: "https://www.cloudflare.com/privacypolicy/",
  hetzner: "https://www.hetzner.com/legal/privacy-policy/",
  quranFoundation: "https://api-docs.quran.foundation/legal/developer-privacy/",
  telegram: "https://telegram.org/privacy",
  resend: "https://resend.com/legal/privacy-policy",
  google: "https://policies.google.com/privacy",
  mozilla: "https://www.mozilla.org/privacy/firefox/",
  apple: "https://www.apple.com/legal/privacy/",
  microsoft: "https://www.microsoft.com/privacy/privacystatement",
  kvkk: "https://www.kvkk.gov.tr/Icerik/6649/Personal-Data-Protection-Law",
};

function internal(locale: Locale, path: string): string {
  return localizedPath(locale, path);
}

const ru = (locale: Locale, config: LegalConfig): AdditionalLegalCopy => ({
  legal: {
    title: "Правовая информация",
    description: "Все документы о правилах сервиса, данных, cookies, удалении аккаунта, безопасности и поставщиках.",
    updated: `Актуально с ${config.effectiveDate}`,
    sections: [
      {
        title: "Основные документы",
        paragraphs: ["Документы применяются к web-версии, будущим мобильным приложениям, Telegram Mini App и другим официальным клиентам Iqro, работающим через общий API."],
        links: [
          { label: "Политика конфиденциальности", href: internal(locale, "/privacy") },
          { label: "Условия использования", href: internal(locale, "/terms") },
          { label: "Политика cookies и локального хранения", href: internal(locale, "/cookies") },
          { label: "Права пользователя и удаление данных", href: internal(locale, "/data-rights") },
        ],
      },
      {
        title: "Прозрачность и связь",
        paragraphs: ["Здесь указаны поставщики инфраструктуры, источники контента и каналы для юридических, privacy- и security-обращений."],
        links: [
          { label: "Поставщики и внешние сервисы", href: internal(locale, "/providers") },
          { label: "Безопасность и сообщение об уязвимости", href: internal(locale, "/security") },
          { label: "Источники и лицензии", href: internal(locale, "/sources") },
          { label: "Контакты и обратная связь", href: internal(locale, "/contacts") },
        ],
      },
      {
        title: "Оператор",
        paragraphs: [`Оператор: ${config.entityName}. Email: ${config.contactEmail}. Почтовый адрес: ${config.postalAddress}. Применимая юрисдикция: ${config.jurisdiction}.`],
      },
    ],
  },
  cookies: {
    title: "Cookies и локальное хранение",
    description: "Какие технические данные сохраняются браузером, зачем они нужны и как ими управлять.",
    updated: `Действует с ${config.effectiveDate}`,
    sections: [
      {
        title: "1. Что используется сейчас",
        paragraphs: ["Iqro использует только механизмы, необходимые для языка, входа, безопасности и синхронизации. Рекламных, поведенческих и аналитических cookies сейчас нет."],
      },
      {
        title: "2. Cookies",
        paragraphs: ["Cookies не содержат пароль. Серверные cookies авторизации недоступны JavaScript в браузере."],
        bullets: [
          "quran_locale_v1 — выбранный язык; до 1 года; SameSite=Lax.",
          "quran_refresh_v1 — продление авторизованной сессии; HttpOnly, Secure в production, SameSite=Lax; удаляется при выходе или истечении refresh-сессии.",
          "quran_installation_id_v1 и quran_installation_credential_v1 — идентификация и защита установки; HttpOnly, Secure в production, SameSite=Lax; до 400 дней.",
        ],
      },
      {
        title: "3. localStorage и sessionStorage",
        paragraphs: ["localStorage хранит локальный cursor, очередь ещё не отправленных изменений, техническое состояние синхронизации, а также последние выбранные на этом устройстве место, метод расчёта намаза и мазхаб Асра. sessionStorage временно хранит безопасный маршрут возврата после входа и одноразовые уведомления об удалении аккаунта. Данные остаются на конкретном устройстве до очистки браузера, выхода или удаления соответствующего состояния приложением."],
      },
      {
        title: "4. Управление",
        paragraphs: ["Можно блокировать или очищать cookies и хранилище в настройках браузера, но тогда язык может сброситься, вход перестанет сохраняться, а неотправленные изменения могут потеряться. Для строго необходимых cookies отдельное согласие не запрашивается. До добавления аналитики, рекламы или иных необязательных технологий будет внедрено отдельное управление согласием и обновлена эта страница."],
        links: [{ label: "Политика конфиденциальности", href: internal(locale, "/privacy") }],
      },
    ],
  },
  dataRights: {
    title: "Права пользователя и удаление данных",
    description: "Как получить, исправить или удалить данные и как удалить аккаунт без установки приложения.",
    updated: `Действует с ${config.effectiveDate}`,
    sections: [
      {
        title: "1. Ваши права",
        paragraphs: ["В пределах применимого закона можно запросить доступ, копию, исправление, удаление, ограничение обработки, возражение, переносимость и отзыв ранее данного согласия. Отзыв не делает незаконной обработку, выполненную до отзыва."],
        links: [{ label: "Закон KVKK и права субъекта данных", href: externalLinks.kvkk }],
      },
      {
        title: "2. Удаление аккаунта через web",
        paragraphs: ["Войдите в web-версию, откройте раздел удаления аккаунта в профиле и подтвердите действие свежим одноразовым кодом из email. Начнётся 7-дневный период отмены; в этот срок удаление можно отменить там же. Устанавливать мобильное приложение повторно не требуется."],
        links: [{ label: "Открыть удаление аккаунта в профиле", href: internal(locale, "/profile#danger-zone-title") }],
      },
      {
        title: "3. Запрос по email",
        paragraphs: [`Если войти не получается, напишите с адреса аккаунта на ${config.contactEmail} с темой «Удаление аккаунта». Не отправляйте пароль или одноразовый код. Для защиты данных мы можем запросить безопасное подтверждение личности. На запрос ответим не позднее 30 дней, если закон не требует быстрее.`],
      },
      {
        title: "4. Что удаляется и когда",
        paragraphs: ["После периода отмены удаляются либо необратимо обезличиваются аккаунт, email-привязка, устройства и credentials, активные сессии, позиция чтения, закладки, напоминания, персональные настройки и связанные обращения, кроме данных, которые необходимо временно сохранить по закону, для безопасности или разрешения спора.", "Рабочая копия удаляется не позднее 30 дней после подтверждённого запроса. Остаточные копии исчезают из ротационных резервных копий не позднее 90 дней и до этого не возвращаются в рабочую систему. Минимальные security-журналы могут храниться ограниченный срок с ограниченным доступом."],
      },
      {
        title: "5. Локальные и внешние данные",
        paragraphs: ["Очистите данные сайта в браузере, чтобы удалить локальную очередь и cookies на устройстве. Удаление Iqro-аккаунта не удаляет независимый Telegram-аккаунт или аккаунты сторонних сервисов. Сейчас Iqro не использует вход через Quran.Foundation; если он появится, здесь будут добавлены отзыв OAuth-доступа и связанное удаление."],
      },
    ],
  },
  providers: {
    title: "Поставщики и внешние сервисы",
    description: "Какие сторонние сервисы участвуют в работе Iqro и какие данные они могут получить.",
    updated: `Актуально с ${config.effectiveDate}`,
    sections: [
      {
        title: "1. Инфраструктура",
        paragraphs: ["Hetzner Cloud размещает серверы приложения, API и базы данных. Cloudflare обслуживает DNS, защитный/CDN-слой и R2 для объектного хранения и доставки аудио. Они могут обрабатывать IP-адрес, технические заголовки, журналы соединений и размещённые нами данные в объёме, необходимом для оказания услуг."],
        links: [
          { label: "Политика конфиденциальности Hetzner", href: externalLinks.hetzner },
          { label: "Политика конфиденциальности Cloudflare", href: externalLinks.cloudflare },
        ],
      },
      {
        title: "2. Коран и аудио",
        paragraphs: ["Quran.Foundation/Quran.com предоставляет Content API и часть источников Quran-контента и аудио. Iqro — независимый сервис и не является официальным приложением Quran.Foundation. Серверные запросы Content API не передают ему email или Iqro-профиль пользователя. При прямой загрузке аудио внешний CDN видит обычные сетевые данные запроса."],
        links: [
          { label: "Quran.Foundation Developer Privacy", href: externalLinks.quranFoundation },
          { label: "Источники и лицензии Iqro", href: internal(locale, "/sources") },
        ],
      },
      {
        title: "3. Telegram Mini App",
        paragraphs: ["Когда пользователь сам открывает будущую Telegram Mini App, Telegram передаёт предусмотренные платформой launch-данные, а также самостоятельно обрабатывает сведения по своим правилам. Mini App будет принимать только минимально необходимые поля и проверять подпись launch payload. Web-версия не передаёт данные Telegram без использования этой функции."],
        links: [{ label: "Политика конфиденциальности Telegram", href: externalLinks.telegram }],
      },
      {
        title: "4. Email, уведомления и мониторинг",
        paragraphs: ["Resend доставляет одноразовые коды входа и получает адрес получателя, содержимое служебного письма и технические данные доставки. Если пользователь явно разрешает браузерные уведомления, Iqro хранит push-endpoint устройства, ключи подписки, язык и часовой пояс; выбранная браузером push-служба Google, Mozilla, Apple или Microsoft получает endpoint, время отправки, сетевые метаданные и зашифрованное сообщение. Подписку можно отключить в кабинете или настройках браузера. Поставщик внешнего мониторинга ещё не выбран."],
        links: [
          { label: "Политика конфиденциальности Resend", href: externalLinks.resend },
          { label: "Google Privacy Policy", href: externalLinks.google },
          { label: "Firefox Privacy Notice", href: externalLinks.mozilla },
          { label: "Apple Privacy Policy", href: externalLinks.apple },
          { label: "Microsoft Privacy Statement", href: externalLinks.microsoft },
        ],
      },
      {
        title: "5. Наши ограничения",
        paragraphs: ["Мы не продаём персональные данные, не передаём их рекламным брокерам, не используем религиозное поведение для рекламы и не используем пользовательский контент для обучения моделей ИИ без отдельного явного согласия. Доступ поставщиков ограничивается целью услуги, договором и минимально необходимыми данными."],
      },
    ],
  },
  security: {
    title: "Безопасность и сообщение об уязвимости",
    description: "Как безопасно сообщить об уязвимости и чего ожидать после обращения.",
    updated: `Действует с ${config.effectiveDate}`,
    sections: [
      {
        title: "1. Как сообщить",
        paragraphs: [`Отправьте описание на ${config.securityEmail}: затронутый URL или API, воспроизводимые шаги, возможное влияние и безопасное доказательство. Не присылайте пароли, одноразовые коды, полный дамп базы или персональные данные других людей. Мы подтвердим получение и начнём triage критичного сообщения в течение 24 часов.`],
      },
      {
        title: "2. Безопасное исследование",
        paragraphs: ["Не нарушайте доступность сервиса, не применяйте социальную инженерию, не закрепляйтесь в системе, не меняйте чужие данные и не извлекайте больше информации, чем строго нужно для доказательства. Остановитесь при обнаружении персональных данных и сразу сообщите нам. Нагрузочные тесты разрешены только по предварительному письменному согласованию."],
      },
      {
        title: "3. Что уже применяется",
        paragraphs: ["Production-трафик должен идти по TLS. Сессии используют короткоживущий access token и защищённый HttpOnly refresh cookie; для чувствительных операций требуется свежее email-подтверждение. Применяются ограничение частоты, разграничение доступа, security headers, минимизация журналов, ротационные backup и управляемое хранение секретов."],
      },
      {
        title: "4. Инциденты",
        paragraphs: ["Мы локализуем инцидент, сохраняем необходимые доказательства, оцениваем затронутые данные и уведомляем пользователей, регуляторов и затронутых поставщиков в сроки применимого закона. Инцидент, связанный с Quran.Foundation API или данными, будет сообщён Quran.Foundation без неоправданной задержки и с целевым первичным уведомлением в пределах 24 часов."],
        links: [{ label: "Контакты", href: internal(locale, "/contacts") }],
      },
    ],
  },
});

const en = (locale: Locale, config: LegalConfig): AdditionalLegalCopy => ({
  legal: {
    title: "Legal information",
    description: "Documents covering service rules, data, cookies, account deletion, security, and providers.",
    updated: `Current from ${config.effectiveDate}`,
    sections: [
      { title: "Core documents", paragraphs: ["These documents cover the web app, future mobile apps, Telegram Mini App, and other official Iqro clients using the shared API."], links: [
        { label: "Privacy Policy", href: internal(locale, "/privacy") }, { label: "Terms of Use", href: internal(locale, "/terms") }, { label: "Cookies and local storage", href: internal(locale, "/cookies") }, { label: "Data rights and account deletion", href: internal(locale, "/data-rights") },
      ] },
      { title: "Transparency and contact", paragraphs: ["These pages identify infrastructure providers, content sources, and legal, privacy, and security contacts."], links: [
        { label: "Providers and external services", href: internal(locale, "/providers") }, { label: "Security and vulnerability reporting", href: internal(locale, "/security") }, { label: "Sources and licenses", href: internal(locale, "/sources") }, { label: "Contact and feedback", href: internal(locale, "/contacts") },
      ] },
      { title: "Operator", paragraphs: [`Operator: ${config.entityName}. Email: ${config.contactEmail}. Postal address: ${config.postalAddress}. Applicable jurisdiction: ${config.jurisdiction}.`] },
    ],
  },
  cookies: {
    title: "Cookies and local storage", description: "What the browser stores, why it is needed, and how to control it.", updated: `Effective ${config.effectiveDate}`,
    sections: [
      { title: "1. What we use now", paragraphs: ["Iqro uses only mechanisms necessary for language, sign-in, security, and synchronization. We currently use no advertising, behavioral, or analytics cookies."] },
      { title: "2. Cookies", paragraphs: ["Cookies do not contain your password. Server authentication cookies are not available to browser JavaScript."], bullets: ["quran_locale_v1 — selected language; up to one year; SameSite=Lax.", "quran_refresh_v1 — extends an authenticated session; HttpOnly, Secure in production, SameSite=Lax; removed on sign-out or refresh-session expiry.", "quran_installation_id_v1 and quran_installation_credential_v1 — identify and protect an installation; HttpOnly, Secure in production, SameSite=Lax; up to 400 days."] },
      { title: "3. localStorage and sessionStorage", paragraphs: ["localStorage holds the local cursor, unsent change queue, synchronization state, and the last prayer-calculation location, method, and Asr school selected on this device. sessionStorage temporarily holds the safe post-login return path and one-time account-lifecycle notices. Data remains on that device until the browser or the app clears it."] },
      { title: "4. Your controls", paragraphs: ["You can block or clear these technologies in browser settings, but language may reset, sign-in may not persist, and unsent changes may be lost. Strictly necessary cookies do not require a separate consent choice. Before adding analytics, advertising, or another optional technology, we will add consent controls and update this page."], links: [{ label: "Privacy Policy", href: internal(locale, "/privacy") }] },
    ],
  },
  dataRights: {
    title: "Data rights and account deletion", description: "How to access, correct, or erase data and delete an account without installing an app.", updated: `Effective ${config.effectiveDate}`,
    sections: [
      { title: "1. Your rights", paragraphs: ["Subject to applicable law, you may request access, a copy, correction, erasure, restriction, objection, portability, and withdrawal of consent. Withdrawal does not make earlier lawful processing unlawful."], links: [{ label: "KVKK law and data-subject rights", href: externalLinks.kvkk }] },
      { title: "2. Delete through the web", paragraphs: ["Sign in to the web app, open account deletion in your profile, and confirm with a fresh one-time email code. A seven-day cancellation period begins; you can cancel from the same place. Reinstalling a mobile app is not required."], links: [{ label: "Open account deletion in profile", href: internal(locale, "/profile#danger-zone-title") }] },
      { title: "3. Request by email", paragraphs: [`If you cannot sign in, email ${config.contactEmail} from the account address with the subject “Account deletion”. Never send a password or one-time code. We may securely verify identity. We will respond within 30 days unless the law requires sooner.`] },
      { title: "4. What is deleted and when", paragraphs: ["After the cancellation period, we delete or irreversibly de-identify the account, email link, devices and credentials, active sessions, reading position, bookmarks, reminders, personal settings, and related support records, except data temporarily required by law, security, or a dispute.", "The working copy is erased no later than 30 days after the confirmed request. Residual copies age out of rotating backups within 90 days and are not restored to production. Minimal security logs may remain for a limited period under restricted access."] },
      { title: "5. Local and external data", paragraphs: ["Clear site data in the browser to remove the local queue and cookies on that device. Deleting an Iqro account does not delete an independent Telegram or third-party account. Iqro currently does not use Quran.Foundation sign-in; if introduced, OAuth revocation and linked deletion instructions will be added here."] },
    ],
  },
  providers: {
    title: "Providers and external services", description: "Third parties involved in Iqro and the data they may receive.", updated: `Current from ${config.effectiveDate}`,
    sections: [
      { title: "1. Infrastructure", paragraphs: ["Hetzner Cloud hosts application servers, APIs, and databases. Cloudflare provides DNS, a protection/CDN layer, and R2 object storage and audio delivery. They may process IP addresses, technical headers, connection logs, and data we host as needed to provide those services."], links: [{ label: "Hetzner privacy policy", href: externalLinks.hetzner }, { label: "Cloudflare privacy policy", href: externalLinks.cloudflare }] },
      { title: "2. Quran and audio", paragraphs: ["Quran.Foundation/Quran.com provides the Content API and some Quran and audio sources. Iqro is an independent service and is not an official Quran.Foundation app. Server-side Content API requests do not send user email or Iqro profile data. An external CDN sees ordinary network request data when audio loads directly."], links: [{ label: "Quran.Foundation Developer Privacy", href: externalLinks.quranFoundation }, { label: "Iqro sources and licenses", href: internal(locale, "/sources") }] },
      { title: "3. Telegram Mini App", paragraphs: ["When a user chooses to launch the future Telegram Mini App, Telegram supplies platform launch data and separately processes information under its terms. The Mini App will accept only required fields and verify the signed launch payload. The web app does not send data to Telegram without this feature."], links: [{ label: "Telegram Privacy Policy", href: externalLinks.telegram }] },
      { title: "4. Email, notifications, and monitoring", paragraphs: ["Resend delivers one-time sign-in codes and receives the recipient address, service-message content, and delivery metadata. When a user explicitly allows browser notifications, Iqro stores the device push endpoint, subscription keys, language, and time zone; the browser-selected Google, Mozilla, Apple, or Microsoft push service receives the endpoint, delivery time, network metadata, and an encrypted message. The subscription can be disabled in the profile or browser settings. An external-monitoring provider has not been selected yet."], links: [{ label: "Resend Privacy Policy", href: externalLinks.resend }, { label: "Google Privacy Policy", href: externalLinks.google }, { label: "Firefox Privacy Notice", href: externalLinks.mozilla }, { label: "Apple Privacy Policy", href: externalLinks.apple }, { label: "Microsoft Privacy Statement", href: externalLinks.microsoft }] },
      { title: "5. Our limits", paragraphs: ["We do not sell personal data, disclose it to advertising brokers, use religious behavior for advertising, or train AI models on user content without separate explicit consent. Provider access is limited by purpose, contract, and data minimization."] },
    ],
  },
  security: {
    title: "Security and vulnerability reporting", description: "How to report a vulnerability safely and what happens next.", updated: `Effective ${config.effectiveDate}`,
    sections: [
      { title: "1. Reporting", paragraphs: [`Email ${config.securityEmail} with the affected URL or API, reproducible steps, likely impact, and safe proof. Do not send passwords, one-time codes, a full database dump, or other people's personal data. We will acknowledge and begin triage of a critical report within 24 hours.`] },
      { title: "2. Safe research", paragraphs: ["Do not affect availability, use social engineering, establish persistence, change other users' data, or extract more information than strictly necessary to prove the issue. Stop if personal data appears and notify us. Load testing requires prior written permission."] },
      { title: "3. Controls in use", paragraphs: ["Production traffic must use TLS. Sessions use a short-lived access token and protected HttpOnly refresh cookie; sensitive actions require fresh email verification. Controls include rate limiting, access separation, security headers, log minimization, rotating backups, and managed secrets."] },
      { title: "4. Incidents", paragraphs: ["We contain the incident, preserve necessary evidence, assess affected data, and notify users, regulators, and affected providers within applicable deadlines. An incident involving Quran.Foundation APIs or data will be reported without undue delay with a target initial notification within 24 hours."], links: [{ label: "Contact", href: internal(locale, "/contacts") }] },
    ],
  },
});

const ar = (locale: Locale, config: LegalConfig): AdditionalLegalCopy => ({
  legal: {
    title: "المعلومات القانونية", description: "وثائق قواعد الخدمة والبيانات وملفات الارتباط وحذف الحساب والأمن والمزوّدين.", updated: `محدّثة من ${config.effectiveDate}`,
    sections: [
      { title: "الوثائق الأساسية", paragraphs: ["تسري هذه الوثائق على الويب وتطبيقات الهاتف المستقبلية وتطبيق Telegram Mini App والعملاء الرسميين الآخرين لـ Iqro الذين يستخدمون API المشترك."], links: [{ label: "سياسة الخصوصية", href: internal(locale, "/privacy") }, { label: "شروط الاستخدام", href: internal(locale, "/terms") }, { label: "ملفات الارتباط والتخزين المحلي", href: internal(locale, "/cookies") }, { label: "حقوق البيانات وحذف الحساب", href: internal(locale, "/data-rights") }] },
      { title: "الشفافية والتواصل", paragraphs: ["توضح هذه الصفحات مزودي البنية التحتية ومصادر المحتوى وقنوات التواصل القانوني والخصوصية والأمن."], links: [{ label: "المزوّدون والخدمات الخارجية", href: internal(locale, "/providers") }, { label: "الأمن والإبلاغ عن الثغرات", href: internal(locale, "/security") }, { label: "المصادر والتراخيص", href: internal(locale, "/sources") }, { label: "التواصل والملاحظات", href: internal(locale, "/contacts") }] },
      { title: "المشغّل", paragraphs: [`المشغّل: ${config.entityName}. البريد: ${config.contactEmail}. العنوان البريدي: ${config.postalAddress}. الاختصاص: ${config.jurisdiction}.`] },
    ],
  },
  cookies: {
    title: "ملفات الارتباط والتخزين المحلي", description: "ما يحفظه المتصفح ولماذا وكيف يمكنك التحكم فيه.", updated: `سارية من ${config.effectiveDate}`,
    sections: [
      { title: "1. ما نستخدمه الآن", paragraphs: ["يستخدم Iqro الوسائل الضرورية فقط للغة وتسجيل الدخول والأمن والمزامنة. لا نستخدم حاليًا ملفات إعلانية أو سلوكية أو تحليلية."] },
      { title: "2. ملفات الارتباط", paragraphs: ["لا تحتوي الملفات على كلمة مرورك، ولا تستطيع JavaScript في المتصفح قراءة ملفات التحقق الخادمية."], bullets: ["quran_locale_v1 — اللغة المختارة؛ حتى سنة؛ SameSite=Lax.", "quran_refresh_v1 — تجديد الجلسة؛ HttpOnly وSecure في production وSameSite=Lax؛ يحذف عند الخروج أو انتهاء الجلسة.", "quran_installation_id_v1 وquran_installation_credential_v1 — تعريف التثبيت وحمايته؛ HttpOnly وSecure في production وSameSite=Lax؛ حتى 400 يوم."] },
      { title: "3. التخزين المحلي والمؤقت", paragraphs: ["يحفظ localStorage مؤشر المزامنة وطابور التغييرات غير المرسلة والحالة التقنية وآخر موقع وطريقة حساب ومذهب عصر اختيرت على هذا الجهاز. ويحفظ sessionStorage مؤقتًا مسار الرجوع الآمن وإشعارات دورة الحساب. تبقى البيانات على الجهاز حتى يمسحها المتصفح أو التطبيق."] },
      { title: "4. التحكم", paragraphs: ["يمكنك حظر هذه الوسائل أو مسحها، لكن قد تُعاد اللغة ويتوقف استمرار الدخول وتضيع تغييرات غير مرسلة. لا نطلب اختيارًا منفصلًا للملفات الضرورية بحتًا. سنضيف إدارة الموافقة ونحدّث الصفحة قبل أي تحليلات أو إعلانات أو تقنية اختيارية."], links: [{ label: "سياسة الخصوصية", href: internal(locale, "/privacy") }] },
    ],
  },
  dataRights: {
    title: "حقوق البيانات وحذف الحساب", description: "الوصول إلى البيانات وتصحيحها أو حذفها وحذف الحساب من دون تثبيت تطبيق.", updated: `سارية من ${config.effectiveDate}`,
    sections: [
      { title: "1. حقوقك", paragraphs: ["وفق القانون المنطبق يمكنك طلب الوصول والنسخة والتصحيح والحذف والتقييد والاعتراض والنقل وسحب الموافقة. لا يؤثر السحب في مشروعية المعالجة السابقة."], links: [{ label: "قانون KVKK وحقوق صاحب البيانات", href: externalLinks.kvkk }] },
      { title: "2. الحذف عبر الويب", paragraphs: ["سجّل الدخول وافتح قسم حذف الحساب في ملفك وأكّد برمز بريد جديد. تبدأ مهلة إلغاء مدتها 7 أيام ويمكنك الإلغاء من الموضع نفسه. لا حاجة لإعادة تثبيت تطبيق الهاتف."], links: [{ label: "فتح حذف الحساب في الملف", href: internal(locale, "/profile#danger-zone-title") }] },
      { title: "3. الطلب بالبريد", paragraphs: [`إن تعذر الدخول، اكتب من بريد الحساب إلى ${config.contactEmail} بعنوان «حذف الحساب». لا ترسل كلمة مرور أو رمزًا مؤقتًا. قد نتحقق من الهوية بصورة آمنة، ونجيب خلال 30 يومًا ما لم يفرض القانون مدة أقصر.`] },
      { title: "4. ما يُحذف ومتى", paragraphs: ["بعد مهلة الإلغاء نحذف الحساب وربط البريد والأجهزة وبيانات الاعتماد والجلسات وموضع القراءة والعلامات والتذكيرات والإعدادات وسجلات الدعم أو نزيل ارتباطها بالشخص، باستثناء ما يلزم مؤقتًا للقانون أو الأمن أو النزاع.", "تُحذف النسخة العاملة خلال 30 يومًا من الطلب المؤكد، وتختفي البقايا من النسخ الاحتياطية الدورية خلال 90 يومًا ولا تعاد إلى الإنتاج. قد تبقى سجلات أمنية محدودة بوصول مقيد."] },
      { title: "5. البيانات المحلية والخارجية", paragraphs: ["امسح بيانات الموقع في المتصفح لإزالة الطابور والملفات المحلية. حذف حساب Iqro لا يحذف حساب Telegram المستقل أو حساب خدمة أخرى. لا يستخدم Iqro حاليًا دخول Quran.Foundation؛ وسنضيف إلغاء OAuth والحذف المرتبط إذا أُضيف."] },
    ],
  },
  providers: {
    title: "المزوّدون والخدمات الخارجية", description: "الأطراف الخارجية المشاركة في Iqro والبيانات التي قد تتلقاها.", updated: `محدّثة من ${config.effectiveDate}`,
    sections: [
      { title: "1. البنية التحتية", paragraphs: ["تستضيف Hetzner Cloud خوادم التطبيق وAPI وقواعد البيانات. وتقدم Cloudflare خدمات DNS والحماية/CDN وR2 لتخزين الكائنات وتسليم الصوت. قد تعالج عنوان IP والترويسات والسجلات التقنية والبيانات المستضافة بقدر تقديم الخدمة."], links: [{ label: "خصوصية Hetzner", href: externalLinks.hetzner }, { label: "خصوصية Cloudflare", href: externalLinks.cloudflare }] },
      { title: "2. القرآن والصوت", paragraphs: ["توفر Quran.Foundation/Quran.com واجهة Content API وبعض مصادر القرآن والصوت. Iqro خدمة مستقلة وليست تطبيقًا رسميًا للمؤسسة. لا ترسل طلبات API الخادمية بريد المستخدم أو ملفه في Iqro. يرى CDN الخارجي بيانات الشبكة المعتادة عند تحميل الصوت مباشرة."], links: [{ label: "خصوصية مطوري Quran.Foundation", href: externalLinks.quranFoundation }, { label: "مصادر وتراخيص Iqro", href: internal(locale, "/sources") }] },
      { title: "3. Telegram Mini App", paragraphs: ["عندما يفتح المستخدم تطبيق Telegram Mini App المستقبلي، يقدم Telegram بيانات التشغيل ويعالج معلومات منفصلة وفق قواعده. سيقبل التطبيق أقل قدر لازم ويتحقق من توقيع البيانات. لا ترسل نسخة الويب بيانات إلى Telegram دون هذه الوظيفة."], links: [{ label: "سياسة خصوصية Telegram", href: externalLinks.telegram }] },
      { title: "4. البريد والإشعارات والمراقبة", paragraphs: ["تُرسل Resend رموز الدخول لمرة واحدة وتتلقى عنوان المستلم ومحتوى رسالة الخدمة وبيانات التسليم التقنية. عند سماح المستخدم صراحة بإشعارات المتصفح، يحفظ Iqro عنوان push للجهاز ومفاتيح الاشتراك واللغة والمنطقة الزمنية؛ وتتلقى خدمة push التي يختارها المتصفح من Google أو Mozilla أو Apple أو Microsoft العنوان ووقت الإرسال وبيانات الشبكة ورسالة مشفرة. يمكن إلغاء الاشتراك من الملف أو إعدادات المتصفح. لم يُختر مزود مراقبة خارجي بعد."], links: [{ label: "خصوصية Resend", href: externalLinks.resend }, { label: "خصوصية Google", href: externalLinks.google }, { label: "خصوصية Firefox", href: externalLinks.mozilla }, { label: "خصوصية Apple", href: externalLinks.apple }, { label: "خصوصية Microsoft", href: externalLinks.microsoft }] },
      { title: "5. حدودنا", paragraphs: ["لا نبيع البيانات ولا نرسلها إلى وسطاء الإعلان ولا نستخدم السلوك الديني للإعلانات ولا ندرب نماذج الذكاء الاصطناعي على محتوى المستخدم دون موافقة صريحة منفصلة. يقتصر وصول المزوّد على الغرض والعقد والحد الأدنى من البيانات."] },
    ],
  },
  security: {
    title: "الأمن والإبلاغ عن الثغرات", description: "كيفية الإبلاغ الآمن وما الذي يحدث بعده.", updated: `سارية من ${config.effectiveDate}`,
    sections: [
      { title: "1. الإبلاغ", paragraphs: [`راسل ${config.securityEmail} مع URL أو API المتأثر وخطوات قابلة للتكرار والأثر المحتمل ودليل آمن. لا ترسل كلمات مرور أو رموزًا مؤقتة أو نسخة قاعدة كاملة أو بيانات الآخرين. نؤكد الاستلام ونبدأ فرز البلاغ الحرج خلال 24 ساعة.`] },
      { title: "2. البحث الآمن", paragraphs: ["لا تؤثر في التوفر ولا تستخدم الهندسة الاجتماعية ولا تثبت وجودًا دائمًا ولا تغير بيانات الغير ولا تستخرج أكثر مما يلزم للدليل. توقف عند ظهور بيانات شخصية وأبلغنا. يحتاج اختبار الحمل إلى موافقة كتابية مسبقة."] },
      { title: "3. الضوابط", paragraphs: ["يجب أن يستخدم production بروتوكول TLS. تستخدم الجلسة access token قصير العمر وrefresh cookie محميًا، ويتطلب الإجراء الحساس تحقق بريد حديثًا. تشمل الضوابط حدود الطلب والوصول المنفصل وترويسات الأمن وتقليل السجلات والنسخ الدورية وإدارة الأسرار."] },
      { title: "4. الحوادث", paragraphs: ["نحتوي الحادث ونحفظ الدليل اللازم ونقيّم البيانات ونخطر المستخدمين والجهات والمزوّدين ضمن المهل القانونية. نبلغ Quran.Foundation دون تأخير غير مبرر عن حادث يتعلق بواجهاتها أو بياناتها، بهدف إشعار أولي خلال 24 ساعة."], links: [{ label: "التواصل", href: internal(locale, "/contacts") }] },
    ],
  },
});

const tr = (locale: Locale, config: LegalConfig): AdditionalLegalCopy => ({
  legal: {
    title: "Yasal bilgiler", description: "Hizmet kuralları, veriler, çerezler, hesap silme, güvenlik ve sağlayıcı belgeleri.", updated: `${config.effectiveDate} tarihinden itibaren güncel`,
    sections: [
      { title: "Temel belgeler", paragraphs: ["Bu belgeler web uygulamasını, gelecekteki mobil uygulamaları, Telegram Mini App'i ve ortak API'yi kullanan diğer resmî Iqro istemcilerini kapsar."], links: [{ label: "Gizlilik Politikası", href: internal(locale, "/privacy") }, { label: "Kullanım Koşulları", href: internal(locale, "/terms") }, { label: "Çerezler ve yerel depolama", href: internal(locale, "/cookies") }, { label: "Veri hakları ve hesap silme", href: internal(locale, "/data-rights") }] },
      { title: "Şeffaflık ve iletişim", paragraphs: ["Bu sayfalar altyapı sağlayıcılarını, içerik kaynaklarını ve yasal, gizlilik ve güvenlik iletişim kanallarını açıklar."], links: [{ label: "Sağlayıcılar ve harici hizmetler", href: internal(locale, "/providers") }, { label: "Güvenlik ve açık bildirimi", href: internal(locale, "/security") }, { label: "Kaynaklar ve lisanslar", href: internal(locale, "/sources") }, { label: "İletişim ve geri bildirim", href: internal(locale, "/contacts") }] },
      { title: "İşletmeci", paragraphs: [`İşletmeci: ${config.entityName}. E-posta: ${config.contactEmail}. Posta adresi: ${config.postalAddress}. Uygulanacak yetki alanı: ${config.jurisdiction}.`] },
    ],
  },
  cookies: {
    title: "Çerezler ve yerel depolama", description: "Tarayıcının ne sakladığı, neden gerektiği ve nasıl yönetileceği.", updated: `${config.effectiveDate} tarihinden itibaren geçerlidir`,
    sections: [
      { title: "1. Şu anda kullandıklarımız", paragraphs: ["Iqro yalnızca dil, oturum açma, güvenlik ve eşitleme için gerekli mekanizmaları kullanır. Şu anda reklam, davranış veya analiz çerezi kullanmıyoruz."] },
      { title: "2. Çerezler", paragraphs: ["Çerezler parolanızı içermez. Sunucu kimlik doğrulama çerezlerine tarayıcı JavaScript'i erişemez."], bullets: ["quran_locale_v1 — seçilen dil; bir yıla kadar; SameSite=Lax.", "quran_refresh_v1 — oturumu yeniler; production'da HttpOnly ve Secure, SameSite=Lax; çıkışta veya oturum süresi dolunca silinir.", "quran_installation_id_v1 ve quran_installation_credential_v1 — kurulumu tanımlar ve korur; production'da HttpOnly ve Secure, SameSite=Lax; 400 güne kadar."] },
      { title: "3. localStorage ve sessionStorage", paragraphs: ["localStorage yerel cursor'ı, gönderilmemiş değişiklik kuyruğunu, eşitleme durumunu ve bu cihazda seçilen son namaz hesaplama konumunu, yöntemini ve ikindi mezhebini tutar. sessionStorage güvenli giriş dönüş yolunu ve tek kullanımlık hesap bildirimlerini geçici tutar. Tarayıcı veya uygulama temizleyene kadar cihazda kalır."] },
      { title: "4. Kontrolleriniz", paragraphs: ["Tarayıcıdan engelleyebilir veya temizleyebilirsiniz; dil sıfırlanabilir, oturum kalıcı olmaz ve gönderilmemiş değişiklikler kaybolabilir. Kesinlikle gerekli çerezler için ayrı seçim istemeyiz. Analiz, reklam veya başka isteğe bağlı teknoloji eklemeden önce rıza yönetimi ekleyip bu sayfayı güncelleyeceğiz."], links: [{ label: "Gizlilik Politikası", href: internal(locale, "/privacy") }] },
    ],
  },
  dataRights: {
    title: "Veri hakları ve hesap silme", description: "Verilere erişme, düzeltme veya silme ve uygulama kurmadan hesap silme.", updated: `${config.effectiveDate} tarihinden itibaren geçerlidir`,
    sections: [
      { title: "1. Haklarınız", paragraphs: ["Uygulanacak hukuk kapsamında erişim, kopya, düzeltme, silme, kısıtlama, itiraz, taşınabilirlik ve rızayı geri alma talep edebilirsiniz. Geri alma önceki hukuka uygun işlemleri geçersiz kılmaz."], links: [{ label: "KVKK ve ilgili kişi hakları", href: externalLinks.kvkk }] },
      { title: "2. Web üzerinden silme", paragraphs: ["Web uygulamasında oturum açın, profilinizde hesap silmeyi açın ve yeni bir tek kullanımlık e-posta koduyla doğrulayın. Yedi günlük iptal süresi başlar; aynı yerden iptal edebilirsiniz. Mobil uygulamayı yeniden kurmanız gerekmez."], links: [{ label: "Profilde hesap silmeyi aç", href: internal(locale, "/profile#danger-zone-title") }] },
      { title: "3. E-posta ile talep", paragraphs: [`Giriş yapamıyorsanız hesap adresinizden ${config.contactEmail} adresine “Hesap silme” konusuyla yazın. Parola veya tek kullanımlık kod göndermeyin. Kimliği güvenli biçimde doğrulayabiliriz. Kanun daha kısa süre istemedikçe 30 gün içinde yanıtlarız.`] },
      { title: "4. Ne zaman ne silinir", paragraphs: ["İptal süresinden sonra hesap, e-posta bağlantısı, cihaz ve credentials, oturumlar, okuma konumu, yer imleri, hatırlatıcılar, ayarlar ve ilgili destek kayıtları silinir veya geri döndürülemez biçimde kimliksizleştirilir; yasa, güvenlik veya uyuşmazlık için geçici olarak gerekenler hariçtir.", "Çalışan kopya doğrulanmış talepten sonra en geç 30 günde silinir. Kalıntılar dönen yedeklerden 90 gün içinde çıkar ve production'a geri yüklenmez. Asgari güvenlik kayıtları sınırlı süre ve kısıtlı erişimle kalabilir."] },
      { title: "5. Yerel ve harici veriler", paragraphs: ["Cihazdaki kuyruk ve çerezler için tarayıcı site verilerini temizleyin. Iqro hesabını silmek bağımsız Telegram veya başka hizmet hesabını silmez. Iqro şu anda Quran.Foundation ile giriş kullanmaz; eklenirse OAuth iptali ve bağlantılı silme burada açıklanacaktır."] },
    ],
  },
  providers: {
    title: "Sağlayıcılar ve harici hizmetler", description: "Iqro'nun çalışmasına katılan üçüncü taraflar ve alabilecekleri veriler.", updated: `${config.effectiveDate} tarihinden itibaren güncel`,
    sections: [
      { title: "1. Altyapı", paragraphs: ["Hetzner Cloud uygulama sunucularını, API'leri ve veritabanlarını barındırır. Cloudflare DNS, koruma/CDN katmanı ve R2 nesne depolama ile ses teslimi sağlar. Hizmet için IP adresi, teknik başlık, bağlantı kaydı ve barındırdığımız verileri işleyebilirler."], links: [{ label: "Hetzner gizlilik politikası", href: externalLinks.hetzner }, { label: "Cloudflare gizlilik politikası", href: externalLinks.cloudflare }] },
      { title: "2. Kur'an ve ses", paragraphs: ["Quran.Foundation/Quran.com Content API'yi ve bazı Kur'an ile ses kaynaklarını sağlar. Iqro bağımsızdır ve resmî Quran.Foundation uygulaması değildir. Sunucu API istekleri kullanıcı e-postasını veya Iqro profilini göndermez. Ses doğrudan yüklenirse harici CDN olağan ağ verisini görür."], links: [{ label: "Quran.Foundation Developer Privacy", href: externalLinks.quranFoundation }, { label: "Iqro kaynakları ve lisansları", href: internal(locale, "/sources") }] },
      { title: "3. Telegram Mini App", paragraphs: ["Kullanıcı gelecekteki Telegram Mini App'i açtığında Telegram platform launch verisini sağlar ve kendi kurallarıyla ayrıca işler. Mini App yalnız gerekli alanları alacak ve imzalı payload'ı doğrulayacaktır. Web uygulaması bu özellik olmadan Telegram'a veri göndermez."], links: [{ label: "Telegram Gizlilik Politikası", href: externalLinks.telegram }] },
      { title: "4. E-posta, bildirimler ve izleme", paragraphs: ["Resend tek kullanımlık giriş kodlarını teslim eder; alıcı adresi, hizmet iletisi içeriği ve teknik teslim verilerini alır. Kullanıcı tarayıcı bildirimlerine açıkça izin verirse Iqro cihazın push endpoint'ini, abonelik anahtarlarını, dili ve saat dilimini saklar; tarayıcının seçtiği Google, Mozilla, Apple veya Microsoft push hizmeti endpoint'i, gönderim zamanını, ağ verilerini ve şifreli iletiyi alır. Abonelik profil veya tarayıcı ayarlarından kapatılabilir. Harici izleme sağlayıcısı henüz seçilmedi."], links: [{ label: "Resend gizlilik politikası", href: externalLinks.resend }, { label: "Google gizlilik politikası", href: externalLinks.google }, { label: "Firefox gizlilik bildirimi", href: externalLinks.mozilla }, { label: "Apple gizlilik politikası", href: externalLinks.apple }, { label: "Microsoft gizlilik bildirimi", href: externalLinks.microsoft }] },
      { title: "5. Sınırlarımız", paragraphs: ["Kişisel verileri satmayız, reklam aracısına vermeyiz, dinî davranışı reklam için kullanmayız ve ayrı açık rıza olmadan kullanıcı içeriğiyle yapay zekâ modeli eğitmeyiz. Sağlayıcı erişimi amaç, sözleşme ve veri minimizasyonuyla sınırlıdır."] },
    ],
  },
  security: {
    title: "Güvenlik ve açık bildirimi", description: "Bir açığın güvenle bildirilmesi ve sonraki süreç.", updated: `${config.effectiveDate} tarihinden itibaren geçerlidir`,
    sections: [
      { title: "1. Bildirim", paragraphs: [`Etkilenen URL veya API, tekrarlanabilir adımlar, muhtemel etki ve güvenli kanıtla ${config.securityEmail} adresine yazın. Parola, tek kullanımlık kod, tam veritabanı dökümü veya başkasının verisini göndermeyin. Kritik bildirimi alıp 24 saat içinde triage'a başlamayı hedefleriz.`] },
      { title: "2. Güvenli araştırma", paragraphs: ["Kullanılabilirliği bozmayın, sosyal mühendislik veya kalıcılık kullanmayın, başkasının verisini değiştirmeyin ve kanıt için gerekenden fazlasını çekmeyin. Kişisel veri görünce durup bildirin. Yük testi önceden yazılı izin gerektirir."] },
      { title: "3. Kullanılan kontroller", paragraphs: ["Production trafiği TLS kullanmalıdır. Oturumlar kısa ömürlü access token ve korunan HttpOnly refresh cookie kullanır; hassas işlem yeni e-posta doğrulaması ister. Rate limit, erişim ayrımı, güvenlik başlıkları, kayıt minimizasyonu, dönen yedekler ve yönetilen sırlar uygulanır."] },
      { title: "4. Olaylar", paragraphs: ["Olayı sınırlar, gerekli kanıtı korur, etkilenen veriyi değerlendirir ve kullanıcı, düzenleyici ve sağlayıcıları uygulanacak sürelerde bilgilendiririz. Quran.Foundation API veya verisini etkileyen olay, gereksiz gecikme olmadan ve 24 saat içinde ilk bildirim hedefiyle iletilir."], links: [{ label: "İletişim", href: internal(locale, "/contacts") }] },
    ],
  },
});

export function additionalLegalCopy(locale: Locale, config: LegalConfig): AdditionalLegalCopy {
  if (locale === "en") return en(locale, config);
  if (locale === "ar") return ar(locale, config);
  if (locale === "tr") return tr(locale, config);
  return ru(locale, config);
}
