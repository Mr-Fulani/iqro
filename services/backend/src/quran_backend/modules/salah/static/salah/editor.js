// Course editor of the prayer-learning course (admin). Plain script, no build:
// language view, untranslated highlight and counters, notes order, unsaved
// changes guard, tree search and reordering by drag, and the live step preview.
// The page works without it, only less conveniently.
(function () {
  "use strict";

  const root = document.querySelector(".se");
  if (!root) return;
  const form = document.getElementById("se-form");
  const editable = root.dataset.editable === "1";
  const storage = {
    get(key) {
      try {
        return window.localStorage.getItem(key);
      } catch {
        return null;
      }
    },
    set(key, value) {
      try {
        window.localStorage.setItem(key, value);
      } catch {
        // The choice still applies to this page.
      }
    },
  };

  // Languages: all in columns, or one at a time ------------------------------
  const tabs = Array.from(root.querySelectorAll(".se-tab"));
  const viewButtons = Array.from(root.querySelectorAll(".se-view-switch [data-view]"));

  function showLanguage(code) {
    tabs.forEach((tab) => tab.setAttribute("aria-selected", String(tab.dataset.lang === code)));
    root.querySelectorAll(".se-lang").forEach((cell) => {
      cell.classList.toggle("is-current", cell.dataset.lang === code);
    });
    storage.set("salahEditor.language", code);
    fitAll();
  }

  function fitAll() {
    root.querySelectorAll(".se-form textarea").forEach((textarea) => {
      if (textarea.offsetParent !== null) fitHeight(textarea);
    });
  }

  function setView(view) {
    root.classList.toggle("is-tabs", view === "tabs");
    viewButtons.forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.view === view)));
    storage.set("salahEditor.view", view);
    fitAll();
  }

  viewButtons.forEach((button) => button.addEventListener("click", () => setView(button.dataset.view)));
  tabs.forEach((tab, index) => {
    tab.addEventListener("click", () => showLanguage(tab.dataset.lang));
    tab.addEventListener("keydown", (event) => {
      if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return;
      const next = tabs[(index + (event.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
      next.focus();
      showLanguage(next.dataset.lang);
    });
  });
  if (tabs.length) {
    const saved = storage.get("salahEditor.language");
    showLanguage(tabs.some((tab) => tab.dataset.lang === saved) ? saved : tabs[0].dataset.lang);
    setView(storage.get("salahEditor.view") === "tabs" ? "tabs" : "columns");
  }

  // Untranslated texts: highlight and count as one types ---------------------
  function refreshMissing() {
    const counts = {};
    root.querySelectorAll(".se-form .se-field").forEach((field) => {
      const cells = Array.from(field.querySelectorAll(".se-lang"));
      const filled = cells.map((cell) => cell.querySelector("textarea").value.trim() !== "");
      const required = field.dataset.required === "1";
      const counted = field.dataset.counted !== "0";
      const anyFilled = filled.some(Boolean);
      cells.forEach((cell, index) => {
        const missing = counted && !filled[index] && (required || anyFilled);
        cell.classList.toggle("is-missing", missing);
        if (missing) counts[cell.dataset.lang] = (counts[cell.dataset.lang] || 0) + 1;
      });
    });
    root.querySelectorAll("[data-count-lang]").forEach((badge) => {
      const count = counts[badge.dataset.countLang] || 0;
      badge.textContent = String(count);
      badge.classList.toggle("has-missing", count > 0);
    });
  }

  // A field grows with its text, so a long instruction is read without scrolling.
  function fitHeight(textarea) {
    textarea.style.height = "auto";
    textarea.style.height = `${textarea.scrollHeight + 2}px`;
  }

  function refreshLength(textarea) {
    const hint = textarea.parentElement.querySelector(".se-length");
    const max = Number(textarea.dataset.max || 0);
    if (!hint || !max) return;
    const length = textarea.value.trim().length;
    hint.textContent = length > max * 0.8 ? `${length} / ${max}` : "";
    hint.classList.toggle("is-over", length > max);
  }

  // Notes: add, remove, reorder ---------------------------------------------
  const noteList = root.querySelector(".se-note-list");
  const noteOrder = form && form.querySelector('input[name="notes_order"]');
  const noteTemplate = document.getElementById("se-note-template");
  const live = root.querySelector(".se-live");
  let newNotes = 0;

  function syncNotes() {
    if (!noteList || !noteOrder) return;
    const notes = Array.from(noteList.children);
    noteOrder.value = notes.map((note) => note.dataset.uid).join(",");
    notes.forEach((note, index) => {
      const up = note.querySelector(".se-note-up");
      const down = note.querySelector(".se-note-down");
      if (up) up.disabled = index === 0;
      if (down) down.disabled = index === notes.length - 1;
      const warning = note.querySelector(".se-note-kind").value === "warning";
      note.classList.toggle("is-warning", warning);
      note.querySelector(".se-note-icon").textContent = warning ? "!" : "?";
    });
    const empty = root.querySelector(".se-notes-empty");
    if (empty) empty.hidden = notes.length > 0;
  }

  function announce(text) {
    if (live) live.textContent = text;
  }

  function moveNote(note, delta) {
    const sibling = delta < 0 ? note.previousElementSibling : note.nextElementSibling;
    if (!sibling) return;
    if (delta < 0) noteList.insertBefore(note, sibling);
    else noteList.insertBefore(sibling, note);
    changed();
    note.querySelector(delta < 0 ? ".se-note-up" : ".se-note-down").focus();
    announce(delta < 0 ? "Заметка поднята выше." : "Заметка опущена ниже.");
  }

  if (noteList && editable) {
    noteList.addEventListener("click", (event) => {
      const note = event.target.closest(".se-note");
      if (!note) return;
      if (event.target.closest(".se-note-up")) moveNote(note, -1);
      else if (event.target.closest(".se-note-down")) moveNote(note, 1);
      else if (event.target.closest(".se-note-remove")) {
        const hasText = Array.from(note.querySelectorAll("textarea")).some((area) => area.value.trim());
        if (hasText && !window.confirm("Удалить заметку со всеми её переводами?")) return;
        note.remove();
        changed();
        announce("Заметка удалена. Изменение сохранится кнопкой «Сохранить».");
      }
    });
    noteList.addEventListener("change", (event) => {
      if (event.target.matches(".se-note-kind")) changed();
    });

    // Drag by the handle; the arrows do the same from the keyboard.
    let dragged = null;
    noteList.addEventListener("pointerdown", (event) => {
      const note = event.target.closest(".se-note");
      if (note) note.draggable = Boolean(event.target.closest(".se-note-handle"));
    });
    noteList.addEventListener("dragstart", (event) => {
      dragged = event.target.closest(".se-note");
      if (!dragged) return;
      dragged.classList.add("is-dragging");
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", dragged.dataset.uid);
    });
    noteList.addEventListener("dragover", (event) => {
      const target = event.target.closest(".se-note");
      if (!dragged || !target || target === dragged) return;
      event.preventDefault();
      noteList.querySelectorAll(".is-drop-target").forEach((item) => item.classList.remove("is-drop-target"));
      target.classList.add("is-drop-target");
    });
    noteList.addEventListener("drop", (event) => {
      const target = event.target.closest(".se-note");
      if (!dragged || !target || target === dragged) return;
      event.preventDefault();
      const after = event.clientY > target.getBoundingClientRect().top + target.offsetHeight / 2;
      noteList.insertBefore(dragged, after ? target.nextElementSibling : target);
      changed();
      announce("Заметка перемещена.");
    });
    noteList.addEventListener("dragend", () => {
      if (dragged) dragged.classList.remove("is-dragging");
      noteList.querySelectorAll(".is-drop-target").forEach((item) => item.classList.remove("is-drop-target"));
      dragged = null;
    });
  }

  const addNote = root.querySelector(".se-note-add");
  if (addNote && noteTemplate && noteList) {
    addNote.addEventListener("click", () => {
      newNotes += 1;
      const uid = `new${newNotes}`;
      const html = noteTemplate.innerHTML.replaceAll("__uid__", uid);
      noteList.insertAdjacentHTML("beforeend", html);
      const note = noteList.lastElementChild;
      const current = tabs.find((tab) => tab.getAttribute("aria-selected") === "true");
      if (current) {
        note.querySelectorAll(".se-lang").forEach((cell) => {
          cell.classList.toggle("is-current", cell.dataset.lang === current.dataset.lang);
        });
      }
      changed();
      fitAll();
      const first = root.classList.contains("is-tabs")
        ? note.querySelector(".se-lang.is-current textarea")
        : note.querySelector("textarea");
      if (first) first.focus();
      announce("Добавлена заметка. Выберите тип и напишите текст.");
    });
  }

  // Unsaved changes ---------------------------------------------------------
  let dirty = false;
  const dirtyMark = root.querySelector(".se-dirty");

  function changed() {
    syncNotes();
    refreshMissing();
    renderPreview();
    if (!editable) return;
    dirty = true;
    if (dirtyMark) dirtyMark.hidden = false;
  }

  if (form) {
    form.addEventListener("input", (event) => {
      if (event.target.matches("textarea")) {
        refreshLength(event.target);
        fitHeight(event.target);
      }
      changed();
    });
    form.addEventListener("change", (event) => {
      if (event.target.matches('input[type="file"]')) showChosenFile(event.target);
      changed();
    });
    form.addEventListener("submit", (event) => {
      const deletions = form.querySelectorAll('.se-delete input:checked').length;
      if (deletions && !window.confirm(`Удалить записей: ${deletions}? Они пропадут из черновика.`)) {
        event.preventDefault();
        return;
      }
      syncNotes();
      dirty = false;
    });
    window.addEventListener("beforeunload", (event) => {
      if (!dirty) return;
      event.preventDefault();
      event.returnValue = "";
    });
    document.addEventListener("keydown", (event) => {
      if (!editable || !(event.metaKey || event.ctrlKey) || event.key.toLowerCase() !== "s") return;
      event.preventDefault();
      const save = form.querySelector('button[name="save"]');
      if (save) form.requestSubmit(save);
    });
    form.querySelectorAll("textarea").forEach((textarea) => {
      refreshLength(textarea);
      fitHeight(textarea);
    });
  }

  // Leaving with unsaved edits: the structure buttons ask first.
  function leaveOk() {
    if (!dirty) return true;
    if (!window.confirm("На странице есть несохранённые правки — они пропадут. Продолжить?")) return false;
    dirty = false;
    return true;
  }

  root.querySelectorAll('.se-tree-op, .se-tree-add, .se-structure a, [form="se-structure"][type="submit"]').forEach((control) => {
    control.addEventListener("click", (event) => {
      if (!leaveOk()) event.preventDefault();
    });
  });

  root.querySelectorAll(".se-revert").forEach((button) => {
    button.addEventListener("click", (event) => {
      const question = "Вернуть текст источника? Свой вариант этого текста пропадёт на всех языках, остальные правки на странице сохранятся.";
      if (!window.confirm(question)) event.preventDefault();
    });
  });

  document.querySelectorAll("[data-confirm]").forEach((button) => {
    button.addEventListener("click", (event) => {
      if (dirty) {
        window.alert("Сначала сохраните правки на этой странице.");
        event.preventDefault();
        return;
      }
      if (!window.confirm(button.dataset.confirm)) event.preventDefault();
    });
  });

  // A chosen recording can be heard before it is saved.
  function showChosenFile(input) {
    const box = input.closest("td").querySelector(".se-file-preview");
    if (!box) return;
    box.replaceChildren();
    const file = input.files && input.files[0];
    box.hidden = !file;
    if (!file) return;
    const name = file.name.toLowerCase();
    const note = document.createElement("span");
    note.className = "se-small";
    if (!name.endsWith(".m4a") && !name.endsWith(".mp3")) {
      note.textContent = "Нужен файл .m4a или .mp3 — этот сервер не примет.";
      note.classList.add("se-error");
      box.append(note);
      return;
    }
    const audio = document.createElement("audio");
    audio.controls = true;
    audio.src = URL.createObjectURL(file);
    note.textContent = `Выбрано: ${file.name}, ${Math.max(1, Math.round(file.size / 1024))} КБ — сохранится кнопкой «Сохранить».`;
    box.append(audio, note);
  }

  // Tree: search and «only untranslated» -------------------------------------
  const tree = root.querySelector(".se-tree");
  const search = tree && tree.querySelector(".se-tree-search");
  const missingOnly = tree && tree.querySelector(".se-tree-missing-only");

  function filterTree() {
    const query = search.value.trim().toLowerCase();
    const onlyMissing = missingOnly.checked;
    const visit = (item) => {
      const children = Array.from(item.querySelectorAll(":scope > details > ul > .se-tree-item"));
      const childShown = children.map(visit).some(Boolean);
      const own = (!query || item.dataset.label.includes(query)) && (!onlyMissing || item.classList.contains("has-missing"));
      const shown = own || childShown;
      item.hidden = !shown;
      const details = item.querySelector(":scope > details");
      if (details && (query || onlyMissing) && childShown) details.open = true;
      return shown;
    };
    tree.querySelectorAll(":scope > .se-tree-list > .se-tree-item").forEach(visit);
  }

  if (search && missingOnly) {
    search.addEventListener("input", filterTree);
    missingOnly.addEventListener("change", filterTree);
    // Only the tree scrolls to the open place; the page stays where it is.
    const current = tree.querySelector('[aria-current="page"]');
    if (current) {
      const offset = current.getBoundingClientRect().top - tree.getBoundingClientRect().top;
      tree.scrollTop += offset - tree.clientHeight / 2;
    }
  }

  // Tree: reorder by drag ----------------------------------------------------
  // A section goes before or after a section, a lesson next to a lesson (in that
  // lesson's section), a step next to a step of the same lesson and rak'ah. The
  // arrows do the same without a mouse.
  const structureForm = document.getElementById("se-structure");

  function submitStructure(fields) {
    Object.entries(fields).forEach(([name, value]) => {
      const input = document.createElement("input");
      input.type = "hidden";
      input.name = name;
      input.value = value;
      structureForm.append(input);
    });
    structureForm.submit();
  }

  if (tree && structureForm) {
    let draggedRow = null;
    const clearDrop = () => {
      tree.querySelectorAll(".is-drop-before, .is-drop-after").forEach((item) => {
        item.classList.remove("is-drop-before", "is-drop-after");
      });
    };
    const dropTarget = (event) => {
      let target = event.target.closest && event.target.closest("[data-node]");
      while (target && target.dataset.group !== draggedRow.dataset.group) {
        target = target.parentElement.closest("[data-node]");
      }
      return target && target !== draggedRow && !draggedRow.contains(target) ? target : null;
    };
    const dropsAfter = (event, target) => {
      const row = target.querySelector(":scope > details > summary") || target;
      const box = row.getBoundingClientRect();
      return event.clientY > box.top + box.height / 2;
    };

    tree.addEventListener("pointerdown", (event) => {
      const row = event.target.closest("[data-node]");
      if (row) row.draggable = Boolean(event.target.closest(".se-tree-handle"));
    });
    tree.addEventListener("dragstart", (event) => {
      draggedRow = event.target.closest && event.target.closest("[data-node]");
      if (!draggedRow || !draggedRow.draggable) {
        draggedRow = null;
        return;
      }
      draggedRow.classList.add("is-dragging");
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", draggedRow.dataset.node);
    });
    tree.addEventListener("dragover", (event) => {
      if (!draggedRow) return;
      const target = dropTarget(event);
      clearDrop();
      if (!target) return;
      event.preventDefault();
      target.classList.add(dropsAfter(event, target) ? "is-drop-after" : "is-drop-before");
    });
    tree.addEventListener("drop", (event) => {
      if (!draggedRow) return;
      const target = dropTarget(event);
      if (!target) return;
      event.preventDefault();
      const after = dropsAfter(event, target);
      clearDrop();
      if (!leaveOk()) return;
      submitStructure({
        action: "move",
        node: draggedRow.dataset.node,
        target: target.dataset.node,
        position: after ? "after" : "before",
      });
    });
    tree.addEventListener("dragend", () => {
      if (draggedRow) {
        draggedRow.classList.remove("is-dragging");
        draggedRow.draggable = false;
      }
      clearDrop();
      draggedRow = null;
    });
  }

  // Live preview of a step ---------------------------------------------------
  const previewRoot = root.querySelector("[data-preview-root]");
  const previewData = document.getElementById("se-preview-data");
  const previewLanguage = root.querySelector(".se-preview-lang");
  const preview = previewData ? JSON.parse(previewData.textContent) : null;
  const openNotes = new Set();

  function value(name) {
    const field = form && form.elements.namedItem(name);
    return field && "value" in field ? field.value.trim() : "";
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function textOrMissing(tag, className, text) {
    return text ? element(tag, className, text) : element(tag, `${className} se-p-empty`, "Не переведено");
  }

  function renderPreview() {
    if (!preview || !previewRoot) return;
    const lang = previewLanguage.value;
    previewRoot.replaceChildren();
    previewRoot.dir = lang === "ar" ? "rtl" : "ltr";
    previewRoot.lang = lang;
    if (preview.image) {
      const image = element("img");
      image.src = preview.image.url;
      image.alt = (preview.image.alt && preview.image.alt[lang]) || "";
      image.width = 720;
      image.height = 720;
      previewRoot.append(image);
    }
    const head = element("div", "se-p-head");
    head.append(textOrMissing("h4", "", value(`text-title-${lang}`)));
    if (preview.ruling) head.append(element("span", "se-p-chip", preview.ruling));
    if (preview.rakat) head.append(element("span", "se-p-chip", `Ракаат ${preview.rakat}`));
    previewRoot.append(head);

    const notes = noteList ? Array.from(noteList.children) : [];
    const written = notes
      .map((note) => ({
        uid: note.dataset.uid,
        warning: note.querySelector(".se-note-kind").value === "warning",
        text: value(`note-${note.dataset.uid}-text-${lang}`),
      }))
      .filter((note) => note.text);
    if (written.length) {
      const row = element("div", "se-p-notes");
      written.forEach((note) => {
        const button = element("button", `se-p-note${note.warning ? " is-warning" : ""}`, note.warning ? "!" : "?");
        button.type = "button";
        button.setAttribute("aria-expanded", String(openNotes.has(note.uid)));
        button.setAttribute("aria-label", note.warning ? "Важно" : "Справка");
        button.addEventListener("click", () => {
          if (openNotes.has(note.uid)) openNotes.delete(note.uid);
          else {
            openNotes.clear();
            openNotes.add(note.uid);
          }
          renderPreview();
        });
        row.append(button);
      });
      previewRoot.append(row);
      written.filter((note) => openNotes.has(note.uid)).forEach((note) => {
        previewRoot.append(element("div", "se-p-popover", note.text));
      });
    }

    previewRoot.append(textOrMissing("p", "se-p-instruction", value(`text-instruction-${lang}`)));
    const details = value(`text-details-${lang}`);
    if (details) previewRoot.append(element("p", "se-p-details", details));
    const audio = preview.audio[lang] || preview.audio.all;
    if (audio) {
      const player = element("audio");
      player.controls = true;
      player.preload = "none";
      player.src = audio;
      previewRoot.append(player);
    }
    preview.formulas.forEach((formula) => {
      const card = element("div", "se-p-formula");
      const arabic = element("p", "se-p-arabic", formula.arabic);
      arabic.lang = "ar";
      arabic.dir = "rtl";
      card.append(arabic);
      const texts = formula.texts[lang] || {};
      if (texts.transliteration) card.append(element("p", "se-p-translit", texts.transliteration));
      if (texts.translation) card.append(element("p", "", texts.translation));
      if (formula.repetitions > 1) card.append(element("p", "se-small", `× ${formula.repetitions}`));
      previewRoot.append(card);
    });
  }

  if (previewLanguage) {
    const saved = storage.get("salahEditor.language");
    if (saved && Array.from(previewLanguage.options).some((option) => option.value === saved)) {
      previewLanguage.value = saved;
    }
    previewLanguage.addEventListener("change", renderPreview);
  }

  syncNotes();
  refreshMissing();
  renderPreview();
})();
