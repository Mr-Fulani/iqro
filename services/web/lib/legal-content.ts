import type { Locale } from "./i18n";
import type { LegalConfig } from "./legal-config";

export type LegalSection = {
  title: string;
  paragraphs: string[];
  bullets?: string[];
};

type LegalDocument = {
  title: string;
  description: string;
  updated: string;
  sections: LegalSection[];
};

type ContactCopy = {
  title: string;
  description: string;
  operator: string;
  general: string;
  privacy: string;
  security: string;
  address: string;
  feedbackTitle: string;
  feedbackBody: string;
  feedbackAction: string;
  urgent: string;
};

type SourcesCopy = {
  title: string;
  description: string;
  quranTitle: string;
  audioTitle: string;
  version: string;
  source: string;
  license: string;
  rightsHolder: string;
  attribution: string;
  noQuran: string;
  noAudio: string;
  noticeTitle: string;
  noticeBody: string;
};

export type LegalCopy = {
  privacy: LegalDocument;
  terms: LegalDocument;
  contacts: ContactCopy;
  sources: SourcesCopy;
};

const ru = (config: LegalConfig): LegalCopy => ({
  privacy: {
    title: "Политика конфиденциальности",
    description: "Какие данные обрабатывает Quran Platform, зачем, как долго и как реализовать свои права.",
    updated: `Действует с ${config.effectiveDate}`,
    sections: [
      {
        title: "1. Оператор и область действия",
        paragraphs: [
          `${config.entityName} управляет Quran Platform и выступает оператором данных. Контакт: ${config.contactEmail}. Почтовый адрес: ${config.postalAddress}.`,
          "Политика относится к web-версии, мобильным приложениям, Telegram Mini App и другим официальным клиентам, использующим тот же API.",
        ],
      },
      {
        title: "2. Какие данные мы обрабатываем",
        paragraphs: ["Набор данных зависит от используемых функций."],
        bullets: [
          "технические идентификаторы установки и устройства, версия приложения, язык, часовой пояс, сессии и события безопасности;",
          "email при входе по одноразовому коду и сведения о подтверждении;",
          "позиция чтения, закладки, напоминания, настройки намаза и синхронизации;",
          "тема, текст и история обращений в поддержку;",
          "IP-адрес, request ID и минимальные журналы запросов для защиты, диагностики и ограничения злоупотреблений.",
        ],
      },
      {
        title: "3. Цели и правовые основания",
        paragraphs: [
          "Мы используем данные для предоставления выбранных функций, синхронизации между клиентами, авторизации, поддержки, безопасности, предотвращения злоупотреблений и выполнения юридических обязанностей.",
          "Основанием служит исполнение пользовательского соглашения или действия по вашему запросу, законный интерес в безопасной и надёжной работе, юридическая обязанность либо согласие там, где оно требуется. Применимое основание должно быть подтверждено для выбранной юрисдикции до запуска.",
        ],
      },
      {
        title: "4. Cookies и локальное хранилище",
        paragraphs: [
          "Необходимые HttpOnly cookies хранят refresh-сессию и ключ установки; cookie языка хранит выбранную локаль. В localStorage сохраняются очередь синхронизации и служебное состояние, а sessionStorage — временный маршрут возврата и уведомления. Эти механизмы нужны для запрошенной функциональности, а не для рекламного профилирования.",
        ],
      },
      {
        title: "5. Получатели и передача",
        paragraphs: [
          "Доступ получают только уполномоченные сотрудники и поставщики инфраструктуры, хостинга, email, мониторинга и поддержки в необходимом объёме. Аудио может загружаться с указанного правообладателем внешнего источника; такой запрос раскрывает источнику IP и технические заголовки.",
          "Список поставщиков, страны обработки и механизм трансграничной передачи должны быть утверждены и опубликованы оператором до production-запуска.",
        ],
      },
      {
        title: "6. Сроки хранения и удаление",
        paragraphs: [
          "Email-челленджи штатно очищаются через 24 часа, неактивные auth-сессии — через 90 дней, журналы sync-изменений и операций — через 180 дней. Tombstone закладок и напоминаний хранятся дольше окна офлайн-синхронизации, чтобы удалённые данные не восстановились на старом устройстве.",
          "Удаление аккаунта запускается из кабинета после повторного подтверждения email, имеет 7-дневный период отмены, затем персональные настройки и идентификаторы удаляются или обезличиваются. Резервные копии и обязательные журналы могут исчезать по отдельному ограниченному циклу.",
        ],
      },
      {
        title: "7. Ваши права и обращения",
        paragraphs: [
          `Вы можете запросить доступ, исправление, удаление, ограничение, возражение, переносимость или отзыв согласия в пределах применимого закона. Напишите на ${config.contactEmail}; для защиты аккаунта мы можем проверить личность. Вы также можете обратиться в компетентный надзорный орган.`,
        ],
      },
      {
        title: "8. Дети, безопасность и изменения",
        paragraphs: [
          "Сервис не предназначен для самостоятельного предоставления персональных данных детьми младше возраста, установленного применимым законом; им нужна помощь родителя или опекуна. Мы применяем разграничение доступа, шифрование транспорта, ограниченные сроки хранения и журналирование безопасности, но ни один сервис не может обещать абсолютную защиту.",
          "При существенном изменении обработки мы обновим дату и предоставим дополнительное уведомление, когда этого требует закон.",
        ],
      },
    ],
  },
  terms: {
    title: "Условия использования",
    description: "Правила использования Quran Platform, аккаунта, контента, аудио и расчётов времени намаза.",
    updated: `Действуют с ${config.effectiveDate}`,
    sections: [
      { title: "1. Принятие условий", paragraphs: [`Quran Platform предоставляет ${config.entityName}. Используя сервис, вы принимаете эти условия и Политику конфиденциальности. Если вы не согласны, не используйте сервис.`] },
      { title: "2. Назначение сервиса", paragraphs: ["Сервис помогает читать и слушать Коран, сохранять прогресс, учиться и рассчитывать время намаза. Он не заменяет решение квалифицированного религиозного авторитета. Расчётные времена зависят от координат, метода, мазхаба и локальных правил — сверяйте их с вашей мечетью."] },
      { title: "3. Аккаунт и устройства", paragraphs: ["Можно пользоваться гостевым режимом или войти по email. Вы отвечаете за доступ к email и своим устройствам, должны сообщать о подозрительной активности и не обходить ограничения безопасности. Мы можем прекратить сессии для защиты аккаунта."] },
      { title: "4. Допустимое использование", paragraphs: ["Нельзя вмешиваться в работу сервиса, обходить rate limits и права доступа, массово извлекать данные вопреки опубликованному API-контракту, распространять вредоносный код, нарушать права третьих лиц или использовать обращения для угроз и спама."] },
      { title: "5. Контент, источники и лицензии", paragraphs: ["Текст, разметка, изображения и аудио принадлежат их правообладателям и доступны на условиях, указанных на странице «Источники и лицензии». Доступ к потоку не означает право копировать, перепубликовывать или коммерчески использовать запись. Собственные элементы интерфейса защищены применимым правом."] },
      { title: "6. Доступность и изменения", paragraphs: ["Мы можем исправлять ошибки, добавлять функции, менять внешние источники, временно ограничивать сервис или снимать контент при проблемах с точностью, безопасностью и правами. Для versioned Quran/audio публикаций сохраняется контролируемая процедура публикации и отзыва."] },
      { title: "7. Ограничение ответственности", paragraphs: ["Сервис предоставляется в пределах, допускаемых законом, без обещания непрерывной или безошибочной работы. Мы не ограничиваем ответственность там, где это запрещено. Перед решениями, зависящими от точного времени или религиозного постановления, используйте авторитетный локальный источник."] },
      { title: "8. Применимое право и контакт", paragraphs: [`Применимое право и место разрешения споров: ${config.jurisdiction}, если обязательные нормы вашей страны не устанавливают иное. Вопросы направляйте на ${config.contactEmail}. Существенные изменения условий будут отмечены новой датой.`] },
    ],
  },
  contacts: {
    title: "Контакты и обратная связь", description: "Как связаться с оператором, поддержкой и командой безопасности.", operator: "Оператор", general: "Общие и юридические вопросы", privacy: "Запросы о персональных данных", security: "Уязвимости и инциденты", address: "Почтовый адрес", feedbackTitle: "Обращение внутри сервиса", feedbackBody: "В кабинете можно создать обращение с категорией, следить за статусом и продолжать переписку. Для этого нужен гостевой или подтверждённый аккаунт.", feedbackAction: "Открыть кабинет и feedback", urgent: "Не отправляйте пароли, одноразовые коды, платёжные данные или лишние персональные сведения. Для уязвимости используйте security-контакт, а не публичное обращение.",
  },
  sources: {
    title: "Источники и лицензии", description: "Происхождение, версии, правообладатели и условия использования опубликованного Quran и аудио-контента.", quranTitle: "Издания Корана", audioTitle: "Аудиодекламации", version: "Версия", source: "Источник", license: "Лицензия", rightsHolder: "Правообладатель", attribution: "Атрибуция", noQuran: "Нет опубликованных изданий.", noAudio: "Нет опубликованных лицензированных декламаций.", noticeTitle: "Важно", noticeBody: "Публикуются только активные versioned материалы с зафиксированным источником и лицензией. Условия относятся к контенту, а не автоматически ко всему программному продукту. Прямые media URL намеренно не выводятся на этой странице.",
  },
});

const en = (config: LegalConfig): LegalCopy => {
  return {
    privacy: {
      title: "Privacy Policy", description: "What Quran Platform processes, why, for how long, and how to exercise your rights.", updated: `Effective ${config.effectiveDate}`,
      sections: [
        { title: "1. Controller and scope", paragraphs: [`${config.entityName} operates Quran Platform and is the data controller. Contact: ${config.contactEmail}. Postal address: ${config.postalAddress}.`, "This policy covers the web app, mobile apps, Telegram Mini App, and other official clients using the same API."] },
        { title: "2. Data we process", paragraphs: ["The data depends on the features you use."], bullets: ["installation and device identifiers, app version, language, time zone, sessions, and security events;", "email and verification state for one-time-code sign-in;", "reading position, bookmarks, reminders, prayer settings, and sync state;", "support ticket subject, messages, and history;", "IP address, request ID, and minimal request logs for security, diagnostics, and abuse prevention."] },
        { title: "3. Purposes and legal bases", paragraphs: ["We process data to provide requested features, synchronize clients, authenticate users, provide support, secure the service, prevent abuse, and meet legal duties.", "Depending on the activity and applicable law, the basis is performance of the terms or steps you request, legitimate interests in a secure and reliable service, a legal obligation, or consent where required. The operator must confirm the exact basis for the launch jurisdiction."] },
        { title: "4. Cookies and local storage", paragraphs: ["Necessary HttpOnly cookies hold the refresh session and installation key; a locale cookie remembers language. localStorage holds the sync queue and operational state, while sessionStorage holds temporary return paths and notices. These mechanisms support requested functionality and are not used for advertising profiles."] },
        { title: "5. Recipients and transfers", paragraphs: ["Access is limited to authorized staff and necessary infrastructure, hosting, email, monitoring, and support providers. Audio may load from a rights holder's external source, which receives your IP address and technical request headers.", "The operator must approve and publish the actual providers, processing countries, and transfer safeguards before production launch."] },
        { title: "6. Retention and deletion", paragraphs: ["Email challenges are normally removed after 24 hours, inactive auth sessions after 90 days, and sync change/operation logs after 180 days. Bookmark and reminder tombstones outlive the offline-sync window so old devices cannot resurrect deleted records.", "Account deletion is requested in the profile after fresh email verification, has a 7-day cancellation period, and then deletes or de-identifies personal settings and identifiers. Backups and legally required logs may follow a separate, limited cycle."] },
        { title: "7. Your rights", paragraphs: [`Subject to applicable law, you may request access, correction, deletion, restriction, objection, portability, or withdrawal of consent. Email ${config.contactEmail}; we may verify identity to protect the account. You may also complain to the competent supervisory authority.`] },
        { title: "8. Children, security, and changes", paragraphs: ["The service is not intended for children below the age at which they may independently provide personal data under applicable law; a parent or guardian should assist them. We use access controls, transport encryption, bounded retention, and security logging, but no service can promise absolute security.", "If processing changes materially, we will update the date and provide additional notice where required."] },
      ],
    },
    terms: {
      title: "Terms of Use", description: "Rules for Quran Platform, accounts, content, audio, and prayer-time calculations.", updated: `Effective ${config.effectiveDate}`,
      sections: [
        { title: "1. Acceptance", paragraphs: [`Quran Platform is provided by ${config.entityName}. By using it, you accept these terms and the Privacy Policy. Do not use the service if you disagree.`] },
        { title: "2. Purpose", paragraphs: ["The service helps users read and listen to the Quran, save progress, learn, and calculate prayer times. It does not replace a qualified religious authority. Calculations depend on coordinates, method, madhhab, and local practice; verify them with your local mosque."] },
        { title: "3. Accounts and devices", paragraphs: ["You may use guest mode or sign in by email. You are responsible for access to your email and devices, reporting suspicious activity, and not bypassing security controls. We may revoke sessions to protect an account."] },
        { title: "4. Acceptable use", paragraphs: ["Do not disrupt the service, bypass rate limits or authorization, scrape beyond the published API contract, distribute malware, infringe third-party rights, or use support channels for threats or spam."] },
        { title: "5. Content and licenses", paragraphs: ["Quran text, layout, images, and audio remain subject to their rights holders and the terms shown on Sources and licenses. Streaming permission does not grant a right to copy, republish, or commercially exploit a recording. Original interface elements are protected under applicable law."] },
        { title: "6. Availability and changes", paragraphs: ["We may fix errors, add functions, change external sources, temporarily restrict service, or withdraw content for accuracy, security, or rights reasons. Versioned Quran/audio content follows a controlled publication and withdrawal process."] },
        { title: "7. Liability", paragraphs: ["To the extent permitted by law, the service is provided without a promise of uninterrupted or error-free operation. Nothing excludes liability that cannot legally be excluded. For decisions requiring exact time or a religious ruling, use an authoritative local source."] },
        { title: "8. Law and contact", paragraphs: [`Governing law and forum: ${config.jurisdiction}, unless mandatory consumer rules say otherwise. Contact ${config.contactEmail}. Material changes will carry a new effective date.`] },
      ],
    },
    contacts: { title: "Contact and feedback", description: "Contact the operator, support, privacy, or security team.", operator: "Operator", general: "General and legal enquiries", privacy: "Privacy requests", security: "Vulnerabilities and incidents", address: "Postal address", feedbackTitle: "In-product feedback", feedbackBody: "Create a categorized ticket in your profile, follow its status, and continue the conversation. A guest or verified account is required.", feedbackAction: "Open profile and feedback", urgent: "Do not send passwords, one-time codes, payment data, or unnecessary personal information. Report vulnerabilities through the security contact, not a public ticket." },
    sources: { title: "Sources and licenses", description: "Provenance, versions, rights holders, and usage terms for published Quran and audio content.", quranTitle: "Quran editions", audioTitle: "Audio recitations", version: "Version", source: "Source", license: "License", rightsHolder: "Rights holder", attribution: "Attribution", noQuran: "No published editions.", noAudio: "No published licensed recitations.", noticeTitle: "Important", noticeBody: "Only active versioned material with recorded provenance and licensing is published. Content terms do not automatically apply to the entire software product. Direct media URLs are intentionally omitted from this page." },
  };
};

const ar = (config: LegalConfig): LegalCopy => {
  const copy = en(config);
  return {
    ...copy,
    privacy: {
      title: "سياسة الخصوصية", description: "البيانات التي تعالجها منصة القرآن وأغراضها ومدة حفظها وحقوق المستخدم.", updated: `سارية من ${config.effectiveDate}`,
      sections: [
        { title: "1. المتحكم ونطاق السياسة", paragraphs: [`تدير ${config.entityName} منصة القرآن وهي المتحكم في البيانات. التواصل: ${config.contactEmail}. العنوان البريدي: ${config.postalAddress}.`, "تشمل هذه السياسة تطبيق الويب وتطبيقات الهاتف وتطبيق Telegram Mini App وسائر العملاء الرسميين الذين يستخدمون واجهة API نفسها."] },
        { title: "2. البيانات التي نعالجها", paragraphs: ["تختلف البيانات بحسب الوظائف التي تستخدمها."], bullets: ["معرّفات التثبيت والجهاز وإصدار التطبيق واللغة والمنطقة الزمنية والجلسات وأحداث الأمن؛", "البريد الإلكتروني وحالة التحقق عند الدخول بالرمز المؤقت؛", "موضع القراءة والعلامات والتذكيرات وإعدادات الصلاة وحالة المزامنة؛", "موضوع رسائل الدعم ومحتواها وسجلها؛", "عنوان IP ومعرّف الطلب وسجلات تقنية محدودة للأمن والتشخيص ومنع الإساءة."] },
        { title: "3. الأغراض والأسس القانونية", paragraphs: ["نعالج البيانات لتقديم الوظائف المطلوبة ومزامنة العملاء والتحقق من الهوية والدعم وحماية الخدمة ومنع الإساءة والوفاء بالالتزامات القانونية.", "بحسب النشاط والقانون المنطبق، يستند ذلك إلى تنفيذ الشروط أو اتخاذ خطوات بطلبك أو المصلحة المشروعة في خدمة آمنة وموثوقة أو التزام قانوني أو الموافقة عند لزومها. يجب على المشغّل اعتماد الأساس المحدد في دولة الإطلاق."] },
        { title: "4. ملفات الارتباط والتخزين المحلي", paragraphs: ["تحفظ ملفات HttpOnly الضرورية جلسة التحديث ومفتاح التثبيت، ويحفظ ملف اللغة اختيارك. يحتفظ localStorage بطابور المزامنة والحالة التشغيلية، ويحتفظ sessionStorage بمسار الرجوع والإشعارات المؤقتة. تُستخدم هذه الوسائل للوظائف المطلوبة لا لبناء ملفات إعلانية."] },
        { title: "5. المستلمون ونقل البيانات", paragraphs: ["يقتصر الوصول على الموظفين المخولين ومقدمي البنية التحتية والاستضافة والبريد والمراقبة والدعم بالقدر اللازم. قد يُحمّل الصوت من مصدر خارجي لصاحب الحقوق، فيتلقى المصدر عنوان IP وترويسات الطلب التقنية.", "يجب على المشغّل اعتماد ونشر المزوّدين الفعليين ودول المعالجة وضمانات النقل قبل الإطلاق الإنتاجي."] },
        { title: "6. مدة الحفظ والحذف", paragraphs: ["تُحذف طلبات رمز البريد عادة بعد 24 ساعة، وجلسات الدخول غير النشطة بعد 90 يومًا، وسجلات تغييرات وعمليات المزامنة بعد 180 يومًا. تبقى علامات حذف العلامات والتذكيرات مدة تتجاوز نافذة المزامنة دون اتصال كي لا يعيد جهاز قديم بيانات محذوفة.", "يُطلب حذف الحساب من الملف الشخصي بعد تحقق جديد من البريد، مع مهلة إلغاء 7 أيام، ثم تُحذف الإعدادات والمعرّفات الشخصية أو تزال صلتها بالشخص. قد تتبع النسخ الاحتياطية والسجلات الإلزامية دورة منفصلة ومحدودة."] },
        { title: "7. حقوقك", paragraphs: [`وفق القانون المنطبق، يمكنك طلب الوصول أو التصحيح أو الحذف أو التقييد أو الاعتراض أو نقل البيانات أو سحب الموافقة. راسل ${config.contactEmail}؛ وقد نتحقق من الهوية لحماية الحساب. ويمكنك الشكوى إلى الجهة الرقابية المختصة.`] },
        { title: "8. الأطفال والأمن والتغييرات", paragraphs: ["الخدمة غير مخصصة لأن يقدم طفل دون السن القانونية بياناته الشخصية مستقلًا؛ يجب أن يساعده والد أو ولي. نستخدم التحكم في الوصول وتشفير النقل ومدد حفظ محدودة وسجلات أمنية، لكن لا توجد خدمة تضمن أمنًا مطلقًا.", "عند تغير المعالجة بصورة جوهرية سنحدّث التاريخ ونقدم إشعارًا إضافيًا عندما يقتضي القانون."] },
      ],
    },
    terms: {
      title: "شروط الاستخدام", description: "قواعد استخدام منصة القرآن والحساب والمحتوى والصوت ومواقيت الصلاة.", updated: `سارية من ${config.effectiveDate}`,
      sections: [
        { title: "1. قبول الشروط", paragraphs: [`تقدم ${config.entityName} منصة القرآن. باستخدام الخدمة توافق على هذه الشروط وسياسة الخصوصية. لا تستخدمها إن لم توافق.`] },
        { title: "2. غرض الخدمة", paragraphs: ["تساعد الخدمة على قراءة القرآن والاستماع إليه وحفظ التقدم والتعلم وحساب مواقيت الصلاة. ولا تحل محل مرجع ديني مؤهل. تعتمد الحسابات على الموقع والطريقة والمذهب والعرف المحلي؛ تحقق منها مع مسجدك المحلي."] },
        { title: "3. الحساب والأجهزة", paragraphs: ["يمكنك استخدام وضع الضيف أو الدخول بالبريد. أنت مسؤول عن حماية بريدك وأجهزتك والإبلاغ عن النشاط المشبوه وعدم تجاوز ضوابط الأمن. يجوز لنا إنهاء الجلسات لحماية الحساب."] },
        { title: "4. الاستخدام المقبول", paragraphs: ["يُحظر تعطيل الخدمة أو تجاوز حدود الطلبات والصلاحيات أو جمع البيانات خارج عقد API المنشور أو نشر البرمجيات الخبيثة أو انتهاك حقوق الغير أو استخدام الدعم للتهديد أو الرسائل المزعجة."] },
        { title: "5. المحتوى والتراخيص", paragraphs: ["يظل نص القرآن وتخطيطه وصوره وصوته خاضعًا لحقوق أصحابه والشروط المبينة في صفحة المصادر والتراخيص. إذن البث لا يمنح حق النسخ أو إعادة النشر أو الاستغلال التجاري. عناصر الواجهة الأصلية محمية وفق القانون."] },
        { title: "6. التوفر والتغييرات", paragraphs: ["يجوز لنا إصلاح الأخطاء وإضافة وظائف وتغيير المصادر الخارجية وتقييد الخدمة مؤقتًا أو سحب محتوى لأسباب تتعلق بالدقة أو الأمن أو الحقوق. يخضع محتوى القرآن والصوت ذي الإصدارات لعملية نشر وسحب مضبوطة."] },
        { title: "7. المسؤولية", paragraphs: ["في الحدود التي يسمح بها القانون، لا نعد بتشغيل متواصل خالٍ من الأخطاء. لا نستبعد مسؤولية لا يجوز استبعادها قانونًا. للقرارات التي تتطلب وقتًا دقيقًا أو حكمًا شرعيًا استخدم مصدرًا محليًا موثوقًا."] },
        { title: "8. القانون والتواصل", paragraphs: [`القانون والمحكمة المختصة: ${config.jurisdiction} ما لم تقض قواعد حماية المستهلك الإلزامية بخلاف ذلك. تواصل عبر ${config.contactEmail}. تحمل التغييرات الجوهرية تاريخ سريان جديدًا.`] },
      ],
    },
    contacts: { ...copy.contacts, title: "التواصل والملاحظات", description: "التواصل مع المشغّل والدعم وفريق الخصوصية والأمن.", operator: "المشغّل", general: "الاستفسارات العامة والقانونية", privacy: "طلبات الخصوصية", security: "الثغرات والحوادث", address: "العنوان البريدي", feedbackTitle: "ملاحظات داخل الخدمة", feedbackBody: "يمكنك إنشاء تذكرة مصنفة من الحساب ومتابعة حالتها ومواصلة المحادثة. يلزم حساب ضيف أو حساب موثّق.", feedbackAction: "فتح الحساب والملاحظات", urgent: "لا ترسل كلمات المرور أو الرموز المؤقتة أو بيانات الدفع أو معلومات شخصية غير لازمة. أبلغ عن الثغرات عبر بريد الأمن." },
    sources: { ...copy.sources, title: "المصادر والتراخيص", description: "مصدر وإصدار وحقوق وشروط استخدام محتوى القرآن والصوت المنشور.", quranTitle: "طبعات القرآن", audioTitle: "التلاوات الصوتية", version: "الإصدار", source: "المصدر", license: "الترخيص", rightsHolder: "صاحب الحقوق", attribution: "نَسب المصدر", noQuran: "لا توجد طبعات منشورة.", noAudio: "لا توجد تلاوات مرخصة منشورة.", noticeTitle: "مهم", noticeBody: "لا يُنشر إلا المحتوى النشط ذو الإصدار والمصدر والترخيص المسجلين. لا تسري شروط المحتوى تلقائيًا على المنتج البرمجي كله. لا تُعرض روابط الوسائط المباشرة هنا." },
  };
};

const tr = (config: LegalConfig): LegalCopy => {
  const copy = en(config);
  return {
    ...copy,
    privacy: {
      title: "Gizlilik Politikası", description: "Quran Platform'un işlediği veriler, amaçlar, saklama süreleri ve haklarınız.", updated: `${config.effectiveDate} tarihinden itibaren geçerlidir`,
      sections: [
        { title: "1. Veri sorumlusu ve kapsam", paragraphs: [`Quran Platform, ${config.entityName} tarafından işletilir ve veri sorumlusu bu kuruluştur. İletişim: ${config.contactEmail}. Posta adresi: ${config.postalAddress}.`, "Bu politika web uygulamasını, mobil uygulamaları, Telegram Mini App'i ve aynı API'yi kullanan diğer resmî istemcileri kapsar."] },
        { title: "2. İşlediğimiz veriler", paragraphs: ["Veri kapsamı kullandığınız özelliklere göre değişir."], bullets: ["kurulum ve cihaz tanımlayıcıları, uygulama sürümü, dil, saat dilimi, oturumlar ve güvenlik olayları;", "tek kullanımlık kodla giriş için e-posta ve doğrulama durumu;", "okuma konumu, yer imleri, hatırlatıcılar, namaz ayarları ve senkronizasyon durumu;", "destek talebinin konusu, mesajları ve geçmişi;", "güvenlik, teşhis ve kötüye kullanımı önleme için IP adresi, istek kimliği ve sınırlı teknik kayıtlar."] },
        { title: "3. Amaçlar ve hukuki sebepler", paragraphs: ["Verileri istenen özellikleri sunmak, istemcileri eşitlemek, kimlik doğrulamak, destek vermek, hizmeti korumak, kötüye kullanımı önlemek ve hukuki yükümlülükleri yerine getirmek için işleriz.", "Faaliyete ve uygulanacak hukuka göre dayanak; koşulların ifası veya talebiniz üzerine işlem yapılması, güvenli ve güvenilir hizmete ilişkin meşru menfaat, hukuki yükümlülük ya da gerektiğinde açık rızadır. İşletmeci, yayına alınacak ülke için somut işleme şartını hukuk incelemesinde kesinleştirmelidir."] },
        { title: "4. Çerezler ve yerel depolama", paragraphs: ["Zorunlu HttpOnly çerezleri yenileme oturumunu ve kurulum anahtarını, dil çerezi ise seçiminizi saklar. localStorage senkronizasyon kuyruğunu ve işletim durumunu; sessionStorage geçici dönüş yolunu ve bildirimleri tutar. Bunlar istenen işlevler içindir, reklam profili oluşturmak için kullanılmaz."] },
        { title: "5. Alıcılar ve aktarımlar", paragraphs: ["Erişim, yalnızca yetkili çalışanlar ile gerekli altyapı, barındırma, e-posta, izleme ve destek sağlayıcılarıyla sınırlıdır. Ses, hak sahibinin harici kaynağından yüklenebilir; bu durumda kaynak IP adresinizi ve teknik istek başlıklarını alır.", "İşletmeci, production yayını öncesinde gerçek sağlayıcıları, işleme ülkelerini ve yurt dışı aktarım güvencelerini onaylayıp yayımlamalıdır."] },
        { title: "6. Saklama ve silme", paragraphs: ["E-posta doğrulama talepleri normalde 24 saat, etkin olmayan kimlik doğrulama oturumları 90 gün, senkronizasyon değişiklik ve işlem kayıtları 180 gün sonra temizlenir. Eski cihazların silinen verileri geri getirmemesi için yer imi ve hatırlatıcı silme kayıtları çevrimdışı senkronizasyon penceresinden daha uzun tutulur.", "Hesap silme, profilden yeni e-posta doğrulamasıyla istenir; 7 günlük iptal süresinden sonra kişisel ayarlar ve tanımlayıcılar silinir veya kimliksizleştirilir. Yedekler ve zorunlu kayıtlar ayrı ve sınırlı bir döngü izleyebilir."] },
        { title: "7. Haklarınız", paragraphs: [`Uygulanacak hukuk kapsamında erişim, düzeltme, silme, kısıtlama, itiraz, veri taşınabilirliği veya rızayı geri alma talebinde bulunabilirsiniz. ${config.contactEmail} adresine yazın; hesabı korumak için kimliğinizi doğrulayabiliriz. Yetkili denetim makamına başvurma hakkınız da vardır.`] },
        { title: "8. Çocuklar, güvenlik ve değişiklikler", paragraphs: ["Hizmet, uygulanacak hukuka göre kişisel verisini tek başına sunamayacak yaştaki çocuklar için bağımsız kullanıma yönelik değildir; ebeveyn veya vasi yardımcı olmalıdır. Erişim kontrolleri, aktarım şifrelemesi, sınırlı saklama ve güvenlik kayıtları kullanırız; ancak hiçbir hizmet mutlak güvenlik vaat edemez.", "İşleme esaslı biçimde değişirse tarihi günceller ve hukuken gerektiğinde ayrıca bildirim yaparız."] },
      ],
    },
    terms: {
      title: "Kullanım Koşulları", description: "Quran Platform, hesap, içerik, ses ve namaz vakti hesaplamalarına ilişkin kurallar.", updated: `${config.effectiveDate} tarihinden itibaren geçerlidir`,
      sections: [
        { title: "1. Kabul", paragraphs: [`Quran Platform, ${config.entityName} tarafından sunulur. Hizmeti kullanarak bu koşulları ve Gizlilik Politikası'nı kabul edersiniz. Kabul etmiyorsanız kullanmayın.`] },
        { title: "2. Hizmetin amacı", paragraphs: ["Hizmet Kur'an okumaya ve dinlemeye, ilerlemeyi kaydetmeye, öğrenmeye ve namaz vakitlerini hesaplamaya yardımcı olur. Yetkin bir dinî merciin yerini almaz. Hesaplar konum, yöntem, mezhep ve yerel uygulamaya bağlıdır; yerel caminizle doğrulayın."] },
        { title: "3. Hesap ve cihazlar", paragraphs: ["Misafir modunu kullanabilir veya e-postayla giriş yapabilirsiniz. E-posta ve cihaz erişiminizi korumak, şüpheli etkinliği bildirmek ve güvenlik kontrollerini aşmamak sizin sorumluluğunuzdadır. Hesabı korumak için oturumları sonlandırabiliriz."] },
        { title: "4. Kabul edilebilir kullanım", paragraphs: ["Hizmeti bozamaz, hız ve yetki sınırlarını aşamaz, yayımlanmış API sözleşmesi dışında toplu veri çekemez, zararlı yazılım dağıtamaz, üçüncü kişi haklarını ihlal edemez veya destek kanallarını tehdit ve spam için kullanamazsınız."] },
        { title: "5. İçerik ve lisanslar", paragraphs: ["Kur'an metni, düzeni, görselleri ve sesleri hak sahiplerine ve Kaynaklar ve lisanslar sayfasındaki koşullara tabidir. Akış izni; kaydı kopyalama, yeniden yayımlama veya ticari kullanma hakkı vermez. Özgün arayüz unsurları uygulanacak hukukla korunur."] },
        { title: "6. Kullanılabilirlik ve değişiklikler", paragraphs: ["Hataları düzeltebilir, özellik ekleyebilir, harici kaynakları değiştirebilir, hizmeti geçici sınırlayabilir veya doğruluk, güvenlik ya da haklar nedeniyle içeriği yayından kaldırabiliriz. Sürümlü Kur'an ve ses içeriği kontrollü yayın ve geri çekme sürecine tabidir."] },
        { title: "7. Sorumluluk", paragraphs: ["Hukukun izin verdiği ölçüde kesintisiz veya hatasız çalışma sözü verilmez. Kanunen sınırlandırılamayan sorumluluklar saklıdır. Kesin zaman veya dinî hüküm gerektiren kararlar için yetkili bir yerel kaynak kullanın."] },
        { title: "8. Hukuk ve iletişim", paragraphs: [`Zorunlu tüketici hükümleri aksini gerektirmedikçe uygulanacak hukuk ve yetkili yer: ${config.jurisdiction}. İletişim: ${config.contactEmail}. Esaslı değişiklikler yeni yürürlük tarihiyle yayımlanır.`] },
      ],
    },
    contacts: { ...copy.contacts, title: "İletişim ve geri bildirim", description: "İşletmeci, destek, gizlilik ve güvenlik ekibiyle iletişim kurun.", operator: "Veri sorumlusu / işletmeci", general: "Genel ve hukuki sorular", privacy: "Kişisel veri başvuruları", security: "Güvenlik açıkları ve olaylar", address: "Posta adresi", feedbackTitle: "Uygulama içi geri bildirim", feedbackBody: "Profilinizden kategorili bir talep oluşturabilir, durumunu izleyebilir ve yazışmayı sürdürebilirsiniz. Misafir veya doğrulanmış hesap gerekir.", feedbackAction: "Profil ve geri bildirimi aç", urgent: "Parola, tek kullanımlık kod, ödeme verisi veya gereksiz kişisel bilgi göndermeyin. Güvenlik açıklarını güvenlik adresine bildirin." },
    sources: { ...copy.sources, title: "Kaynaklar ve lisanslar", description: "Yayımlanmış Kur'an ve ses içeriğinin kaynağı, sürümü, hak sahipleri ve kullanım koşulları.", quranTitle: "Kur'an baskıları", audioTitle: "Sesli kıraatler", version: "Sürüm", source: "Kaynak", license: "Lisans", rightsHolder: "Hak sahibi", attribution: "Atıf", noQuran: "Yayımlanmış baskı yok.", noAudio: "Yayımlanmış lisanslı kıraat yok.", noticeTitle: "Önemli", noticeBody: "Yalnızca kaynağı ve lisansı kayıtlı etkin sürümlü içerik yayımlanır. İçerik koşulları tüm yazılım ürünü için otomatik olarak geçerli değildir. Doğrudan medya URL'leri bu sayfada özellikle gösterilmez." },
  };
};

export function legalCopy(locale: Locale, config: LegalConfig): LegalCopy {
  if (locale === "en") return en(config);
  if (locale === "ar") return ar(config);
  if (locale === "tr") return tr(config);
  return ru(config);
}
