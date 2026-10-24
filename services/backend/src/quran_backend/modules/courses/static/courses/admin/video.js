// The «Видео» block of a lesson: checks a file in the browser before it is sent,
// uploads it with progress, and redraws the block from the server's answer, so
// the unsaved text of the lesson form stays where it is.
(function () {
  "use strict";

  var VIDEO_EXTENSIONS = ["mp4", "mov"];
  var AUDIO_EXTENSIONS = ["mp3", "m4a", "aac", "wav", "flac"];
  var HANDBRAKE = "пересохраните файл в HandBrake: пресет «Fast 720p30» с галочкой «Web Optimized»";
  var HEVC =
    "Видео в формате HEVC, его покажет не каждый телефон. На iPhone включите " +
    "«Настройки → Камера → Форматы → Наиболее совместимые» или " + HANDBRAKE + ".";
  var TOLERANCE_MS = 2000;
  var uploading = false;

  function csrfToken() {
    var input = document.querySelector('input[name="csrfmiddlewaretoken"]');
    return input ? input.value : "";
  }

  function clock(seconds) {
    var total = Math.round(seconds);
    var hours = Math.floor(total / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    var rest = String(total % 60).padStart(2, "0");
    return hours ? hours + ":" + String(minutes).padStart(2, "0") + ":" + rest : minutes + ":" + rest;
  }

  // The same wording as the server: «2,4 с», «14 с», «1 мин 5 с».
  function length(milliseconds) {
    var seconds = milliseconds / 1000;
    if (seconds < 10) return seconds.toFixed(1).replace(/\.0$/, "").replace(".", ",") + " с";
    var total = Math.round(seconds);
    var minutes = Math.floor(total / 60);
    var rest = total % 60;
    if (!minutes) return rest + " с";
    return rest ? minutes + " мин " + rest + " с" : minutes + " мин";
  }

  function megabytes(bytes) {
    var value = bytes / (1024 * 1024);
    return (value < 10 ? value.toFixed(1).replace(".", ",") : Math.round(value)) + " МБ";
  }

  function say(element, text, kind) {
    element.textContent = text;
    element.classList.remove("is-ok", "is-error", "is-busy");
    if (kind) element.classList.add("is-" + kind);
  }

  // Sample entries of the first and last megabyte: a phone writes the index at the end.
  function codecTags(file) {
    var size = 1024 * 1024;
    var parts = [file.slice(0, size)];
    if (file.size > size) parts.push(file.slice(Math.max(size, file.size - size)));
    return Promise.all(
      parts.map(function (part) {
        return part.arrayBuffer();
      })
    ).then(function (buffers) {
      var chunks = buffers.map(function (buffer) {
        return new Uint8Array(buffer);
      });
      function found(word) {
        return chunks.some(function (bytes) {
          return contains(bytes, word);
        });
      }
      return { hevc: found("hvc1") || found("hev1"), avc: found("avc1") };
    });
  }

  function contains(bytes, word) {
    var a = word.charCodeAt(0);
    var b = word.charCodeAt(1);
    var c = word.charCodeAt(2);
    var d = word.charCodeAt(3);
    for (var index = 0; index + 3 < bytes.length; index += 1) {
      if (bytes[index] === a && bytes[index + 1] === b && bytes[index + 2] === c && bytes[index + 3] === d) {
        return true;
      }
    }
    return false;
  }

  // Duration and frame from a hidden element; null when the browser cannot read the file.
  function metadata(file, tag) {
    return new Promise(function (resolve) {
      var element = document.createElement(tag);
      var url = URL.createObjectURL(file);
      var timer = setTimeout(finish, 8000);
      function finish(result) {
        clearTimeout(timer);
        URL.revokeObjectURL(url);
        element.removeAttribute("src");
        resolve(result || null);
      }
      element.preload = "metadata";
      element.muted = true;
      element.onloadedmetadata = function () {
        finish({
          duration: element.duration,
          width: element.videoWidth || 0,
          height: element.videoHeight || 0,
        });
      };
      element.onerror = function () {
        finish(null);
      };
      element.src = url;
    });
  }

  function extension(name) {
    var dot = name.lastIndexOf(".");
    return dot === -1 ? "" : name.slice(dot + 1).toLowerCase();
  }

  function checkVideo(file, maxMib) {
    if (VIDEO_EXTENSIONS.indexOf(extension(file.name)) === -1) {
      return Promise.resolve({ error: "Нужен файл MP4 или MOV. WebM и другие форматы не подходят: " + HANDBRAKE + "." });
    }
    if (file.size === 0) return Promise.resolve({ error: "Выбранный файл пуст." });
    if (file.size > maxMib * 1024 * 1024) {
      return Promise.resolve({ error: "Файл " + megabytes(file.size) + ", допустимо до " + maxMib + " МБ. " + HANDBRAKE.charAt(0).toUpperCase() + HANDBRAKE.slice(1) + "." });
    }
    return codecTags(file).then(function (tags) {
      if (tags.hevc && !tags.avc) return { error: HEVC };
      return metadata(file, "video").then(function (info) {
        if (!info || !isFinite(info.duration)) {
          return { ok: "Браузер не смог прочитать файл, его проверит сервер. Можно загружать." };
        }
        if (info.duration < 10) return { error: "Видео короче 10 секунд." };
        if (info.duration > 3600) {
          return { error: "Видео длится " + length(info.duration * 1000) + ", допустимо до 60 минут. Разделите тему на части." };
        }
        var long = Math.max(info.width, info.height);
        var short = Math.min(info.width, info.height);
        if (long > 1920 || short > 1080) {
          return { error: "Кадр " + info.width + "×" + info.height + ", допустимо до 1920×1080. " + HANDBRAKE.charAt(0).toUpperCase() + HANDBRAKE.slice(1) + "." };
        }
        var frame = info.width ? ", " + info.width + "×" + info.height : "";
        return { ok: "Можно загружать: " + clock(info.duration) + frame + ", " + megabytes(file.size) + "." };
      });
    });
  }

  function checkAudio(file, maxMib, videoMs) {
    if (AUDIO_EXTENSIONS.indexOf(extension(file.name)) === -1) {
      return Promise.resolve({ error: "Нужен звук MP3, M4A (AAC), WAV или FLAC." });
    }
    if (file.size === 0) return Promise.resolve({ error: "Выбранный файл пуст." });
    if (file.size > maxMib * 1024 * 1024) {
      return Promise.resolve({ error: "Файл " + megabytes(file.size) + ", допустимо до " + maxMib + " МБ." });
    }
    return metadata(file, "audio").then(function (info) {
      if (!info || !isFinite(info.duration)) {
        return { ok: "Браузер не смог прочитать файл, его проверит сервер. Можно загружать." };
      }
      var difference = Math.round(info.duration * 1000) - videoMs;
      if (Math.abs(difference) > TOLERANCE_MS) {
        return {
          error:
            "Озвучка " + (difference < 0 ? "короче" : "длиннее") + " видео на " + length(Math.abs(difference)) +
            ". Длительность должна совпадать с видео (" + clock(videoMs / 1000) + ") с точностью до 2 секунд.",
        };
      }
      return { ok: "Можно загружать: " + clock(info.duration) + ", " + megabytes(file.size) + "." };
    });
  }

  function answer(xhr) {
    var data = {};
    try {
      data = JSON.parse(xhr.responseText);
    } catch (error) {
      data = {};
    }
    if (xhr.status === 413) data.error = "Сервер не принял файл: он слишком большой.";
    if (!data.error && !data.html) data.error = "Ошибка сервера " + xhr.status + ". Повторите.";
    return data;
  }

  function redraw(root, html, message) {
    var holder = document.createElement("div");
    holder.innerHTML = html;
    var fresh = holder.firstElementChild;
    var selected = root.querySelector('[data-video-tab][aria-selected="true"]');
    root.replaceWith(fresh);
    init(fresh);
    // Stay on the language the author was working on.
    var same = selected && document.getElementById(selected.id);
    if (same) same.click();
    if (message) say(fresh.querySelector("[data-video-status]"), message, "ok");
  }

  function setBusy(root, busy) {
    uploading = busy;
    root.querySelectorAll("input, select, button").forEach(function (control) {
      control.disabled = busy;
    });
  }

  function upload(root, box, file) {
    var check = box.querySelector("[data-video-check]");
    var progress = box.querySelector("[data-video-progress]");
    var isAudio = box.getAttribute("data-video-upload") === "audio";
    var form = new FormData();
    form.append("file", file, file.name);
    var speech = box.querySelector("[data-video-speech]");
    if (speech) form.append("spoken_language", speech.value);
    if (box.getAttribute("data-video")) form.append("video", box.getAttribute("data-video"));

    var xhr = new XMLHttpRequest();
    xhr.open("POST", box.getAttribute("data-url"));
    xhr.setRequestHeader("X-CSRFToken", csrfToken());
    xhr.upload.onprogress = function (event) {
      if (!event.lengthComputable) return;
      var percent = Math.round((event.loaded / event.total) * 100);
      progress.value = percent;
      if (event.loaded >= event.total) {
        progress.hidden = true;
        say(check, isAudio ? "Соединение озвучки с видео… Это займёт до пары минут." : "Проверка и сохранение… Это займёт до минуты.");
      } else {
        say(check, "Загрузка… " + percent + " %");
      }
    };
    xhr.onload = function () {
      setBusy(root, false);
      progress.hidden = true;
      var data = answer(xhr);
      if (data.html) {
        redraw(root, data.html, isAudio ? "Готово: озвучка сохранена." : "Готово: видео сохранено.");
      } else {
        say(check, data.error, xhr.status === 409 ? "busy" : "error");
      }
    };
    xhr.onerror = function () {
      setBusy(root, false);
      progress.hidden = true;
      say(check, "Соединение прервалось. Загрузите файл заново.", "error");
    };
    setBusy(root, true);
    progress.hidden = false;
    progress.value = 0;
    say(check, "Загрузка… 0 %");
    xhr.send(form);
  }

  function initUpload(root, box) {
    var input = box.querySelector("[data-video-file]");
    var start = box.querySelector("[data-video-start]");
    var check = box.querySelector("[data-video-check]");
    var chosen = null;

    function choose(file) {
      chosen = null;
      start.hidden = true;
      if (!file) return;
      say(check, "Проверка файла…");
      var maxMib = Number(box.getAttribute("data-max-mib"));
      var verdict =
        box.getAttribute("data-video-upload") === "audio"
          ? checkAudio(file, maxMib, Number(box.getAttribute("data-duration-ms")))
          : checkVideo(file, maxMib);
      verdict.then(function (result) {
        if (result.error) {
          say(check, file.name + ": " + result.error, "error");
          return;
        }
        chosen = file;
        say(check, file.name + ". " + result.ok, "ok");
        start.hidden = false;
        start.focus();
      });
    }

    input.addEventListener("change", function () {
      choose(input.files[0]);
    });
    start.addEventListener("click", function () {
      if (chosen) upload(root, box, chosen);
    });
    if (box.classList.contains("cvid-drop")) {
      box.addEventListener("dragover", function (event) {
        event.preventDefault();
        box.classList.add("is-over");
      });
      box.addEventListener("dragleave", function () {
        box.classList.remove("is-over");
      });
      box.addEventListener("drop", function (event) {
        event.preventDefault();
        box.classList.remove("is-over");
        if (!uploading && event.dataTransfer.files.length) choose(event.dataTransfer.files[0]);
      });
    }
  }

  function initAction(root, form) {
    var status = root.querySelector("[data-video-status]");
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      var question = form.getAttribute("data-video-confirm");
      if (question && !window.confirm(question)) return;
      var body = new FormData(form);
      setBusy(root, true);
      say(status, "Сохранение…");
      fetch(form.action, {
        method: "POST",
        body: body,
        headers: { "X-CSRFToken": csrfToken() },
        credentials: "same-origin",
      })
        .then(function (response) {
          return response.text().then(function (text) {
            return answer({ status: response.status, responseText: text });
          });
        })
        .then(function (data) {
          setBusy(root, false);
          if (data.html) redraw(root, data.html, "Сохранено.");
          else say(status, data.error, "error");
        })
        .catch(function () {
          setBusy(root, false);
          say(status, "Соединение прервалось. Повторите.", "error");
        });
    });
    form.querySelectorAll("[data-video-autosubmit]").forEach(function (control) {
      control.addEventListener("change", function () {
        form.requestSubmit();
      });
    });
  }

  function initTabs(root) {
    var tabs = Array.prototype.slice.call(root.querySelectorAll("[data-video-tab]"));
    tabs.forEach(function (tab, index) {
      tab.addEventListener("click", function () {
        tabs.forEach(function (other) {
          var selected = other === tab;
          other.setAttribute("aria-selected", selected ? "true" : "false");
          other.tabIndex = selected ? 0 : -1;
          document.getElementById(other.getAttribute("aria-controls")).hidden = !selected;
        });
      });
      tab.addEventListener("keydown", function (event) {
        var step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
        if (!step) return;
        var next = tabs[(index + step + tabs.length) % tabs.length];
        next.focus();
        next.click();
      });
      tab.tabIndex = tab.getAttribute("aria-selected") === "true" ? 0 : -1;
    });
  }

  function init(root) {
    root.querySelectorAll("[data-video-upload]").forEach(function (box) {
      initUpload(root, box);
    });
    root.querySelectorAll("form[data-video-action]").forEach(function (form) {
      initAction(root, form);
    });
    initTabs(root);
    // «Взять кадр на N с» follows the player: pause where the poster should be.
    var player = root.querySelector("[data-video-player]");
    var second = root.querySelector("[data-video-second]");
    if (player && second) {
      ["pause", "seeked"].forEach(function (name) {
        player.addEventListener(name, function () {
          second.value = Math.floor(player.currentTime);
        });
      });
    }
  }

  window.addEventListener("beforeunload", function (event) {
    if (uploading) event.preventDefault();
  });

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-course-video]").forEach(init);
  });
})();
