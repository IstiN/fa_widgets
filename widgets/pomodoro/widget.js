// Pomodoro — 25 min focus / 5 min break cycles (every 4th break is 15 min).
// start/pause/reset/skip, completed-pomodoro counter persisted via
// jsr.storage (ASYNC — read with .then, never synchronously).
// The ring is an flChart pie (done vs left) with a large centerSpaceRadius.
// All colors from jsr.theme; every state change re-renders via jsr.render.
(function() {
  var FOCUS_SEC = 25 * 60;
  var BREAK_SEC = 5 * 60;
  var LONG_BREAK_SEC = 15 * 60;

  var state = {
    mode: 'focus',      // 'focus' | 'break'
    remaining: FOCUS_SEC,
    running: false,
    completed: 0,       // persisted in storage under 'completed'
    endsAt: 0           // Date.now() timestamp when the phase ends (running only)
  };

  function phaseSeconds() {
    if (state.mode === 'focus') return FOCUS_SEC;
    // Every 4th break is a long one.
    return state.completed > 0 && state.completed % 4 === 0
      ? LONG_BREAK_SEC
      : BREAK_SEC;
  }

  function mmss(sec) {
    var m = Math.floor(sec / 60);
    var s = sec % 60;
    return (m < 10 ? '0' : '') + m + ':' + (s < 10 ? '0' : '') + s;
  }

  function finishPhase(countCompleted) {
    if (state.mode === 'focus') {
      if (countCompleted) {
        state.completed += 1;
        jsr.storage.set('completed', state.completed);
      }
      state.mode = 'break';
    } else {
      state.mode = 'focus';
    }
    state.remaining = phaseSeconds();
    state.endsAt = state.running ? Date.now() + state.remaining * 1000 : 0;
  }

  function tick() {
    if (!state.running) return;
    var left = Math.round((state.endsAt - Date.now()) / 1000);
    if (left <= 0) {
      finishPhase(true);
    } else if (left !== state.remaining) {
      state.remaining = left;
    } else {
      return; // nothing changed — skip the re-render
    }
    render();
  }

  function ring(t) {
    var total = phaseSeconds();
    var done = total - state.remaining;
    var accent = state.mode === 'focus' ? t.accent : t.accent2;
    return {
      type: 'sizedBox', width: 230, height: 230,
      child: {
        type: 'stack',
        children: [
          {
            type: 'flChart',
            chartType: 'pie',
            centerSpaceRadius: 96,
            sections: [
              { value: done > 0 ? done : 0.0001, color: accent },
              { value: state.remaining > 0 ? state.remaining : 0.0001, color: t.surfaceAlt }
            ]
          },
          {
            type: 'center',
            child: {
              type: 'column', mainAxisSize: 'min',
              children: [
                {
                  type: 'text', data: mmss(state.remaining),
                  style: { color: t.text, fontSize: 44, fontWeight: 'w700', letterSpacing: 2.0 }
                },
                { type: 'sizedBox', height: 4 },
                {
                  type: 'text',
                  data: state.mode === 'focus' ? 'FOCUS' : (phaseSeconds() === LONG_BREAK_SEC ? 'LONG BREAK' : 'BREAK'),
                  style: { color: accent, fontSize: 12, fontWeight: 'w600', letterSpacing: 2.5 }
                }
              ]
            }
          }
        ]
      }
    };
  }

  function cycleDots(t) {
    // One dot per pomodoro in the current 4-cycle; filled = done.
    var filled = state.completed % 4;
    if (state.completed > 0 && filled === 0) filled = 4; // just finished a full cycle
    var dots = [];
    for (var i = 0; i < 4; i++) {
      dots.push(i < filled
        ? { type: 'text', data: '🍅', style: { fontSize: 18 } }
        : { type: 'text', data: '○', style: { fontSize: 18, color: t.borderBright } });
      if (i < 3) dots.push({ type: 'sizedBox', width: 6 });
    }
    return { type: 'row', mainAxisAlignment: 'center', children: dots };
  }

  function render() {
    var t = jsr.theme;
    jsr.exportState({
      mode: state.mode,
      remaining: state.remaining,
      running: state.running,
      completed: state.completed
    });
    jsr.render({
      type: 'container',
      color: t.bg,
      child: {
        type: 'center',
        child: {
          type: 'column', mainAxisSize: 'min', crossAxisAlignment: 'center',
          children: [
            ring(t),
            { type: 'sizedBox', height: 20 },
            cycleDots(t),
            { type: 'sizedBox', height: 20 },
            {
              type: 'row', mainAxisAlignment: 'center',
              children: [
                {
                  type: 'button',
                  text: state.running ? 'Pause' : 'Start',
                  style: { backgroundColor: state.mode === 'focus' ? t.accent : t.accent2, foregroundColor: t.onAccent },
                  onTap: 'start_pause'
                },
                { type: 'sizedBox', width: 10 },
                { type: 'outlinedButton', text: 'Reset', onTap: 'reset' },
                { type: 'sizedBox', width: 10 },
                { type: 'textButton', text: 'Skip', onTap: 'skip' }
              ]
            },
            { type: 'sizedBox', height: 16 },
            {
              type: 'text',
              data: 'Completed: ' + state.completed + ' pomodoro' + (state.completed === 1 ? '' : 's'),
              style: { color: t.muted, fontSize: 12 }
            }
          ]
        }
      }
    });
  }

  jsr.onEvent(function(name) {
    if (name === 'start_pause') {
      state.running = !state.running;
      state.endsAt = state.running
        ? Date.now() + state.remaining * 1000
        : 0;
    }
    if (name === 'reset') {
      state.running = false;
      state.mode = 'focus';
      state.remaining = FOCUS_SEC;
      state.endsAt = 0;
    }
    if (name === 'skip') {
      // Finish the phase now; skipping a focus counts it as completed.
      finishPhase(state.mode === 'focus');
    }
    render();
  });

  // jsr.storage.get is ASYNC — hydrate the counter, then re-render.
  jsr.storage.get('completed').then(function(value) {
    var n = parseInt(value, 10);
    if (!isNaN(n) && n > 0) {
      state.completed = n;
      render();
    }
  });

  jsr.setTitle('🍅 Pomodoro');
  setInterval(tick, 1000);
  render();
})();
