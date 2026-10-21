/* The app's bridge to the 3D scene (based on the owner's salah-embed.js, docs/salah/salah-3d.md).
   Page -> app through the JavaScriptChannel "SalahBridge", JSON:
     {"type":"LOADED"}                      scripts ran and WebGL works; waiting for salah.show()
     {"type":"READY","version":"0.1.0"}     the first frame of the step is drawn
     {"type":"STEP_CHANGED","stepIndex":4,"stepId":"sujud"}
     {"type":"ERROR","code":"NO_WEBGL" | "SCRIPTS_NOT_LOADED" | "MOUNT_FAILED" | "CONTEXT_LOST"}
   App -> page: salah.show(stepId, speed), salah.play(), salah.pause(), salah.setSpeed(0.5|0.75|1),
   salah.resetCamera(), salah.dispose(). */
(function () {
  'use strict';
  function send(msg) {
    try { window.SalahBridge.postMessage(JSON.stringify(msg)); } catch (e) { /* no host */ }
  }
  if (!window.THREE || !window.SalahScene) { send({ type: 'ERROR', code: 'SCRIPTS_NOT_LOADED' }); return; }
  var probe = document.createElement('canvas');
  var gl = probe.getContext('webgl2') || probe.getContext('webgl');
  if (!gl) { send({ type: 'ERROR', code: 'NO_WEBGL' }); return; }
  var lose = gl.getExtension('WEBGL_lose_context');
  if (lose) lose.loseContext();

  var canvas = document.getElementById('salah');
  var scene = null;
  canvas.addEventListener('webglcontextlost', function () { if (scene) send({ type: 'ERROR', code: 'CONTEXT_LOST' }); });
  function call(name, value) { if (scene) scene[name](value); }
  window.salah = {
    show: function (step, speed) {
      if (scene) { scene.setStep(step); return; }
      try {
        scene = window.SalahScene.mount(canvas, {
          view: 'full', step: step, speed: speed || 1,
          onStep: function (i, s) { send({ type: 'STEP_CHANGED', stepIndex: i, stepId: s ? s.id : null }); }
        });
      } catch (e) { send({ type: 'ERROR', code: 'MOUNT_FAILED' }); return; }
      requestAnimationFrame(function () { send({ type: 'READY', version: window.SalahScene.version }); });
    },
    play: function () { call('play'); },
    pause: function () { call('pause'); },
    setSpeed: function (v) { call('setSpeed', [0.5, 0.75, 1].indexOf(v) >= 0 ? v : 1); },
    resetCamera: function () { call('resetCamera'); },
    dispose: function () { var s = scene; scene = null; if (s) s.dispose(); }
  };
  send({ type: 'LOADED' });
})();
