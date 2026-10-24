// The «Медиа» block of a lesson: video, slides and banners in the author's order.
// Every button posts to the block's URL and the block is drawn anew from the
// server's answer, so the unsaved text of the lesson form stays where it is.
// Captions save themselves when a field is left and keep the focus.
(function () {
  "use strict";

  var language = null;
  var busy = false;

  function csrfToken() {
    var input = document.querySelector('input[name="csrfmiddlewaretoken"]');
    return input ? input.value : "";
  }

  function say(root, text, kind) {
    var status = root.querySelector("[data-media-status]");
    status.textContent = text;
    status.classList.remove("is-ok", "is-error", "is-busy");
    if (kind) status.classList.add("is-" + kind);
  }

  function answer(status, text) {
    var data = {};
    try {
      data = JSON.parse(text);
    } catch (error) {
      data = {};
    }
    if (status === 413) data.error = "Сервер не принял файлы: они слишком большие. Загрузите меньше за раз.";
    if (!data.error && !data.html && !data.ok) data.error = "Ошибка сервера " + status + ". Повторите.";
    return data;
  }

  function setBusy(root, value) {
    busy = value;
    root.classList.toggle("is-busy", value);
    root.querySelectorAll(".cmedia-head button, .cmedia-add button, .cslide-head button, [data-media-file], [data-media-add], [data-media-common]").forEach(function (control) {
      control.disabled = value || control.hasAttribute("data-media-locked");
    });
  }

  // Sends one action; files go with XMLHttpRequest for the upload progress.
  function send(root, fields, files, done) {
    var form = new FormData();
    Object.keys(fields).forEach(function (name) {
      var value = fields[name];
      if (Array.isArray(value)) {
        value.forEach(function (item) {
          form.append(name, item);
        });
      } else {
        form.append(name, value);
      }
    });
    (files || []).forEach(function (file) {
      form.append("file", file, file.name);
    });
    var xhr = new XMLHttpRequest();
    xhr.open("POST", root.getAttribute("data-url"));
    xhr.setRequestHeader("X-CSRFToken", csrfToken());
    if (files && files.length) {
      xhr.upload.onprogress = function (event) {
        if (!event.lengthComputable) return;
        if (event.loaded >= event.total) {
          say(root, files.length > 1 ? "Обработка картинок (" + files.length + ")…" : "Обработка картинки…", "busy");
        } else {
          say(root, "Загрузка… " + Math.round((event.loaded / event.total) * 100) + " %", "busy");
        }
      };
    }
    xhr.onload = function () {
      setBusy(root, false);
      var data = answer(xhr.status, xhr.responseText);
      if (data.error) {
        say(root, data.error, xhr.status === 409 ? "busy" : "error");
      } else {
        done(data);
      }
    };
    xhr.onerror = function () {
      setBusy(root, false);
      say(root, "Соединение прервалось. Повторите.", "error");
    };
    setBusy(root, true);
    if (!files || !files.length) say(root, "Сохранение…", "busy");
    xhr.send(form);
  }

  function act(root, fields, files, message) {
    send(root, fields, files, function (data) {
      if (data.html) redraw(root, data.html, message || "Сохранено.");
    });
  }

  function redraw(root, html, message) {
    var holder = document.createElement("div");
    holder.innerHTML = html;
    var fresh = holder.firstElementChild;
    root.replaceWith(fresh);
    init(fresh);
    // The video block inside has its own script: it starts on this event.
    fresh.dispatchEvent(new CustomEvent("lesson-media:drawn", { bubbles: true }));
    if (message) say(fresh, message, "ok");
  }

  function isImage(file) {
    return /^image\/(jpeg|png|webp)$/.test(file.type) || /\.(jpe?g|png|webp)$/i.test(file.name);
  }

  function images(root, list, single) {
    var files = Array.prototype.slice.call(list || []);
    var wrong = files.filter(function (file) {
      return !isImage(file);
    });
    if (wrong.length) {
      say(root, wrong[0].name + ": нужна картинка JPEG, PNG или WebP.", "error");
      return null;
    }
    if (!files.length) return null;
    if (single && files.length > 1) {
      say(root, "Выберите одну картинку.", "error");
      return null;
    }
    return files;
  }

  // Order -------------------------------------------------------------------

  function ids(list, attribute) {
    return Array.prototype.map.call(list.querySelectorAll(":scope > [" + attribute + "]"), function (item) {
      return item.getAttribute(attribute);
    });
  }

  // Drag by the handle only: the fields and players inside stay usable.
  function sortable(root, list, attribute, handle, save) {
    if (!list) return;
    var dragged = null;
    var before = null;
    list.querySelectorAll(":scope > [" + attribute + "]").forEach(function (item) {
      var grip = item.querySelector("[" + handle + "]");
      if (!grip || grip.closest("[" + attribute + "]") !== item) return;
      grip.addEventListener("mousedown", function () {
        item.draggable = true;
      });
      grip.addEventListener("mouseup", function () {
        item.draggable = false;
      });
      item.addEventListener("dragstart", function (event) {
        if (!item.draggable) return;
        event.stopPropagation();
        dragged = item;
        before = ids(list, attribute).join(",");
        event.dataTransfer.effectAllowed = "move";
        event.dataTransfer.setData("text/plain", item.getAttribute(attribute));
        item.classList.add("is-dragged");
      });
      item.addEventListener("dragend", function (event) {
        event.stopPropagation();
        item.draggable = false;
        item.classList.remove("is-dragged");
        if (dragged && ids(list, attribute).join(",") !== before) save(ids(list, attribute));
        dragged = null;
      });
    });
    list.addEventListener("dragover", function (event) {
      if (!dragged || dragged.parentNode !== list) return;
      event.preventDefault();
      event.stopPropagation();
      var target = event.target.closest("[" + attribute + "]");
      if (!target || target === dragged || target.parentNode !== list) return;
      var box = target.getBoundingClientRect();
      var horizontal = list.classList.contains("cslides");
      var after = horizontal
        ? event.clientX > box.left + box.width / 2
        : event.clientY > box.top + box.height / 2;
      list.insertBefore(dragged, after ? target.nextSibling : target);
    });
  }

  function moveBy(list, item, attribute, step) {
    var order = ids(list, attribute);
    var index = order.indexOf(item.getAttribute(attribute));
    var target = index + step;
    if (index < 0 || target < 0 || target >= order.length) return null;
    order.splice(index, 1);
    order.splice(target, 0, item.getAttribute(attribute));
    return order;
  }

  // Languages ---------------------------------------------------------------

  function showLanguage(root, code) {
    language = code;
    root.querySelectorAll("[data-media-tab]").forEach(function (tab) {
      var selected = tab.getAttribute("data-media-tab") === code;
      tab.setAttribute("aria-selected", selected ? "true" : "false");
      tab.tabIndex = selected ? 0 : -1;
    });
    root.querySelectorAll("[data-media-panel]").forEach(function (panel) {
      panel.hidden = panel.getAttribute("data-media-panel") !== code;
    });
  }

  function initTabs(root) {
    root.querySelectorAll("[role=tablist]").forEach(function (list) {
      var tabs = Array.prototype.slice.call(list.querySelectorAll("[data-media-tab]"));
      tabs.forEach(function (tab, index) {
        tab.addEventListener("click", function () {
          showLanguage(root, tab.getAttribute("data-media-tab"));
        });
        tab.addEventListener("keydown", function (event) {
          var step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
          if (!step) return;
          var next = tabs[(index + step + tabs.length) % tabs.length];
          next.click();
          next.focus();
        });
      });
    });
    var first = root.querySelector("[data-media-tab]");
    if (first) showLanguage(root, language || first.getAttribute("data-media-tab"));
  }

  // Captions ----------------------------------------------------------------

  function initTexts(root) {
    root.querySelectorAll("[data-media-text]").forEach(function (field) {
      if (field.readOnly) return;
      field.addEventListener("change", function () {
        var panel = field.closest("[data-media-panel]");
        var code = field.getAttribute("data-language");
        var caption = panel.querySelector('[data-media-text="caption"]');
        var alt = panel.querySelector('[data-media-text="alt"]');
        var fields = {
          action: "texts",
          block: field.closest("[data-media-block]").getAttribute("data-media-block"),
          slide: field.closest("[data-media-slide]").getAttribute("data-media-slide"),
          language: code,
          caption: caption.value,
          alt: alt.value,
        };
        var form = new FormData();
        Object.keys(fields).forEach(function (name) {
          form.append(name, fields[name]);
        });
        say(root, "Сохранение подписи…", "busy");
        fetch(root.getAttribute("data-url"), {
          method: "POST",
          body: form,
          headers: { "X-CSRFToken": csrfToken() },
          credentials: "same-origin",
        })
          .then(function (response) {
            return response.text().then(function (text) {
              return answer(response.status, text);
            });
          })
          .then(function (data) {
            if (data.error) say(root, data.error, "error");
            else say(root, "Подпись сохранена (" + code.toUpperCase() + ").", "ok");
          })
          .catch(function () {
            say(root, "Подпись не сохранилась: соединение прервалось. Измените поле ещё раз.", "error");
          });
      });
    });
  }

  // The block ---------------------------------------------------------------

  function dropZone(root, zone, fields, single) {
    zone.addEventListener("dragover", function (event) {
      if (busy || event.dataTransfer.types.indexOf("Files") === -1) return;
      event.preventDefault();
      zone.classList.add("is-over");
    });
    zone.addEventListener("dragleave", function () {
      zone.classList.remove("is-over");
    });
    zone.addEventListener("drop", function (event) {
      if (event.dataTransfer.types.indexOf("Files") === -1) return;
      event.preventDefault();
      zone.classList.remove("is-over");
      var files = images(root, event.dataTransfer.files, single);
      if (files) act(root, fields(), files, "Готово: картинки сохранены.");
    });
  }

  function init(root) {
    var list = root.querySelector("[data-media-list]");
    sortable(root, list, "data-media-block", "data-media-handle", function (order) {
      act(root, { action: "order", order: order }, null, "Порядок сохранён.");
    });
    root.querySelectorAll("[data-slide-list]").forEach(function (slides) {
      var block = slides.closest("[data-media-block]").getAttribute("data-media-block");
      sortable(root, slides, "data-media-slide", "data-slide-handle", function (order) {
        act(root, { action: "slide_order", block: block, order: order }, null, "Порядок слайдов сохранён.");
      });
    });

    root.querySelectorAll("[data-media-block]").forEach(function (item) {
      var block = item.getAttribute("data-media-block");
      var head = item.querySelector(".cmedia-head");
      head.querySelectorAll("[data-media-move]").forEach(function (button) {
        button.addEventListener("click", function () {
          var order = moveBy(list, item, "data-media-block", Number(button.getAttribute("data-media-move")));
          if (order) act(root, { action: "order", order: order }, null, "Порядок сохранён.");
        });
      });
      var remove = head.querySelector("[data-media-remove]");
      if (remove) {
        remove.addEventListener("click", function () {
          if (window.confirm(remove.getAttribute("data-confirm"))) {
            act(root, { action: "remove", block: block }, null, "Блок удалён.");
          }
        });
      }
      if (item.getAttribute("data-media-type") === "video") return;
      var single = item.getAttribute("data-media-type") === "banner";
      item.querySelectorAll('[data-media-file="images"]').forEach(function (input) {
        input.addEventListener("change", function () {
          var files = images(root, input.files, single);
          if (files) act(root, { action: "images", block: block }, files, "Готово: картинки сохранены.");
        });
      });
      if (!single) {
        dropZone(root, item, function () {
          return { action: "images", block: block };
        }, false);
      }
      item.querySelectorAll("[data-media-slide]").forEach(function (slide) {
        var id = slide.getAttribute("data-media-slide");
        var slides = slide.parentNode;
        slide.querySelectorAll("[data-slide-move]").forEach(function (button) {
          button.addEventListener("click", function () {
            var order = moveBy(slides, slide, "data-media-slide", Number(button.getAttribute("data-slide-move")));
            if (order) act(root, { action: "slide_order", block: block, order: order }, null, "Порядок слайдов сохранён.");
          });
        });
        var drop = slide.querySelector("[data-slide-remove]");
        if (drop) {
          drop.addEventListener("click", function () {
            if (window.confirm(drop.getAttribute("data-confirm"))) {
              act(root, { action: "slide_remove", block: block, slide: id }, null, "Слайд удалён.");
            }
          });
        }
        slide.querySelectorAll('[data-media-file="language_image"]').forEach(function (input) {
          input.addEventListener("change", function () {
            var files = images(root, input.files, true);
            var fields = { action: "language_image", block: block, slide: id, language: input.getAttribute("data-language") };
            if (files) act(root, fields, files, "Готово: картинка сохранена.");
          });
        });
        slide.querySelectorAll("[data-media-common]").forEach(function (button) {
          button.addEventListener("click", function () {
            var fields = { action: "language_image_remove", block: block, slide: id, language: button.getAttribute("data-media-common") };
            act(root, fields, null, "Слайд снова с общей картинкой.");
          });
        });
      });
    });

    root.querySelectorAll("[data-media-add]").forEach(function (control) {
      var kind = control.getAttribute("data-media-add");
      if (kind === "video") {
        control.addEventListener("click", function () {
          act(root, { action: "add", kind: "video" }, null, "Добавлено место для видео: загрузите его в новом блоке.");
        });
        return;
      }
      control.addEventListener("change", function () {
        var files = images(root, control.files, kind === "banner");
        if (files) act(root, { action: "add", kind: kind }, files, kind === "banner" ? "Готово: баннер добавлен." : "Готово: слайды добавлены.");
      });
    });
    var zone = root.querySelector("[data-media-drop]");
    if (zone) {
      dropZone(root, zone, function () {
        return { action: "add", kind: "slides" };
      }, false);
    }
    initTabs(root);
    initTexts(root);
  }

  window.addEventListener("beforeunload", function (event) {
    if (busy) event.preventDefault();
  });

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-lesson-media]").forEach(init);
  });
})();
