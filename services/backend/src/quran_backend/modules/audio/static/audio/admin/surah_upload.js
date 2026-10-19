// Uploads whole-surah MP3 files to a recitation, one request per file, so a
// long surah never shares a request with others and each shows its own result.
(function () {
  "use strict";

  function surahFromName(name) {
    var match = /^\s*0*(\d{1,3})(?!\d)/.exec(name);
    if (!match) return "";
    var number = Number(match[1]);
    return number >= 1 && number <= 114 ? String(number) : "";
  }

  function csrfToken() {
    var input = document.querySelector('input[name="csrfmiddlewaretoken"]');
    return input ? input.value : "";
  }

  function cell(text) {
    var td = document.createElement("td");
    td.textContent = text;
    return td;
  }

  function setStatus(row, text, kind) {
    row.status.textContent = text;
    row.status.style.color =
      kind === "error" ? "var(--error-fg, #ba2121)" : kind === "ok" ? "var(--message-success-bg, #2e7d32)" : "";
  }

  function send(url, row) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", url);
      xhr.setRequestHeader("X-CSRFToken", csrfToken());
      xhr.upload.onprogress = function (event) {
        if (!event.lengthComputable) return;
        if (event.loaded >= event.total) {
          setStatus(row, "Проверка и сохранение…");
        } else {
          setStatus(row, "Загрузка… " + Math.round((event.loaded / event.total) * 100) + "%");
        }
      };
      xhr.onload = function () {
        var data = {};
        try {
          data = JSON.parse(xhr.responseText);
        } catch (error) {
          data = {};
        }
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(data);
        } else if (xhr.status === 413) {
          reject(new Error("Сервер не принял файл: он слишком большой."));
        } else {
          reject(new Error(data.error || "Ошибка сервера " + xhr.status + ". Повторите."));
        }
      };
      xhr.onerror = function () {
        reject(new Error("Соединение прервалось. Повторите загрузку."));
      };
      var form = new FormData();
      form.append("surah_number", row.number.value);
      form.append("file", row.file, row.file.name);
      xhr.send(form);
    });
  }

  function init(root) {
    var input = root.querySelector("[data-surah-files]");
    var queue = root.querySelector("[data-surah-queue]");
    var start = root.querySelector("[data-surah-start]");
    var maxBytes = Number(root.getAttribute("data-max-mib")) * 1024 * 1024;
    var rows = [];

    input.addEventListener("change", function () {
      queue.replaceChildren();
      rows = Array.prototype.slice
        .call(input.files)
        .sort(function (a, b) {
          return a.name.localeCompare(b.name, undefined, { numeric: true });
        })
        .map(function (file) {
          var tr = document.createElement("tr");
          var megabytes = (file.size / (1024 * 1024)).toFixed(1);
          tr.appendChild(cell(file.name + " · " + megabytes + " МБ"));
          var numberCell = document.createElement("td");
          var number = document.createElement("input");
          number.type = "number";
          number.min = "1";
          number.max = "114";
          number.style.width = "5em";
          number.value = surahFromName(file.name);
          number.setAttribute("aria-label", "Номер суры для " + file.name);
          numberCell.appendChild(number);
          tr.appendChild(numberCell);
          var status = cell("");
          tr.appendChild(status);
          queue.appendChild(tr);
          var row = { file: file, number: number, status: status, done: false, tooBig: false };
          if (file.size > maxBytes) {
            row.tooBig = true;
            setStatus(row, "Больше " + root.getAttribute("data-max-mib") + " МБ", "error");
          } else {
            setStatus(row, number.value ? "Ожидает" : "Укажите номер суры");
          }
          return row;
        });
      start.disabled = rows.length === 0;
    });

    start.addEventListener("click", async function () {
      start.disabled = true;
      input.disabled = true;
      var added = 0;
      for (var index = 0; index < rows.length; index += 1) {
        var row = rows[index];
        if (row.done || row.tooBig) continue;
        if (!row.number.value) {
          setStatus(row, "Укажите номер суры", "error");
          continue;
        }
        setStatus(row, "Загрузка… 0%");
        try {
          var result = await send(root.getAttribute("data-surah-upload"), row);
          row.done = true;
          row.number.disabled = true;
          added += 1;
          setStatus(row, "Готово: сура " + result.surah_number, "ok");
        } catch (error) {
          setStatus(row, error.message, "error");
        }
      }
      input.disabled = false;
      start.disabled = rows.every(function (row) {
        return row.done || row.tooBig;
      });
      if (added > 0 && !root.querySelector("[data-surah-reload]")) {
        var note = document.createElement("p");
        note.setAttribute("data-surah-reload", "");
        var link = document.createElement("a");
        link.href = window.location.pathname;
        link.textContent = "Обновить страницу, чтобы увидеть список сур";
        note.appendChild(link);
        root.appendChild(note);
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-surah-upload]").forEach(init);
  });
})();
