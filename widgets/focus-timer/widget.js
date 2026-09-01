// Focus Timer widget — pomodoro-style 25/5 cycles on the jsr JSON UI API.
(function () {
  // Hand-drawn SVG flag (24×24 viewBox) — no emoji fonts.
  var FLAG_ICON = '<svg viewBox="0 0 24 24"><path d="M6 3v18" stroke="#94a3b8" stroke-width="1.8" stroke-linecap="round"/><path d="M6.5 3.5h10l-2.5 4 2.5 4h-10z" fill="#a78bfa"/></svg>';

  var FOCUS_SECONDS = 25 * 60;
  var BREAK_SECONDS = 5 * 60;

  var mode = 'focus'; // 'focus' | 'break'
  var viewport = null; // {width, height} once the host reports it
  var remaining = FOCUS_SECONDS;
  var running = false;
  var timerId = null;
  // jsr.storage.get returns a PROMISE (async bridge) — a sync
  // Number(jsr.storage.get(...) || 0) reads NaN. Load, then re-render.
  var completedCycles = 0;
  jsr.storage.get('cycles').then(function (saved) {
    completedCycles = Number(saved || 0);
    render();
  });

  function totalSeconds() {
    return mode === 'focus' ? FOCUS_SECONDS : BREAK_SECONDS;
  }

  function fmt(sec) {
    var m = Math.floor(sec / 60).toString().padStart(2, '0');
    var s = (sec % 60).toString().padStart(2, '0');
    return m + ':' + s;
  }

  function accent() {
    return mode === 'focus' ? '#8b7cf6' : '#22c55e';
  }

  function stopTick() {
    if (timerId !== null) {
      clearInterval(timerId);
      timerId = null;
    }
  }

  function tick() {
    remaining -= 1;
    if (remaining <= 0) {
      stopTick();
      running = false;
      if (mode === 'focus') {
        completedCycles += 1;
        jsr.storage.set('cycles', String(completedCycles));
        switchMode('break');
      } else {
        switchMode('focus');
      }
      return;
    }
    render();
  }

  function switchMode(nextMode) {
    mode = nextMode;
    remaining = totalSeconds();
    jsr.setTitle(mode === 'focus' ? 'Focus Timer' : 'Break Timer');
    render();
  }

  function start() {
    if (running) return;
    running = true;
    timerId = setInterval(tick, 1000);
    render();
  }

  function pause() {
    running = false;
    stopTick();
    render();
  }

  function reset() {
    running = false;
    stopTick();
    remaining = totalSeconds();
    render();
  }

  function handleEvent(actionId) {
    if (actionId === 'toggle') {
      if (running) pause();
      else start();
    } else if (actionId === 'reset') {
      reset();
    } else if (actionId === 'skip') {
      running = false;
      stopTick();
      switchMode(mode === 'focus' ? 'break' : 'focus');
    }
  }

  function ringProgress() {
    return totalSeconds() > 0 ? (totalSeconds() - remaining) / totalSeconds() : 0;
  }

  // Tiles come in many sizes — a short viewport (2x2 tile ≈ 160px,
  // landing cards) gets the compact face: time + start/pause + reset,
  // no header/progress/cycles (they never fit and clip ugly).
  function isCompact() {
    return viewport != null && viewport.height > 0 && viewport.height < 210;
  }

  function render() {
    var progress = ringProgress();
    var timeColor = mode === 'focus' ? '#fbbf24' : '#4ade80';

    if (isCompact()) {
      jsr.render({
        type: 'container',
        padding: [10, 8, 10, 8],
        child: {
          type: 'column',
          mainAxisAlignment: 'center',
          crossAxisAlignment: 'center',
          children: [
            {
              type: 'text',
              data: fmt(remaining),
              style: {
                color: timeColor,
                fontSize: 30,
                fontWeight: 'w700',
                textAlign: 'center',
              },
            },
            { type: 'sizedBox', height: 4 },
            {
              type: 'text',
              data: mode === 'focus' ? 'FOCUS' : 'BREAK',
              style: { color: '#64748b', fontSize: 10, fontWeight: 'w600' },
            },
            { type: 'sizedBox', height: 8 },
            {
              type: 'row',
              mainAxisAlignment: 'center',
              children: [
                {
                  type: 'gestureDetector',
                  onTap: 'toggle',
                  child: {
                    type: 'container',
                    decoration: { color: accent(), borderRadius: 16 },
                    padding: [12, 6, 12, 6],
                    child: {
                      type: 'text',
                      data: running ? 'Pause' : 'Start',
                      style: {
                        color: '#0f172a',
                        fontSize: 12,
                        fontWeight: 'w700',
                      },
                    },
                  },
                },
                { type: 'sizedBox', width: 10 },
                {
                  type: 'gestureDetector',
                  onTap: 'reset',
                  child: {
                    type: 'text',
                    data: 'Reset',
                    style: { color: '#94a3b8', fontSize: 12 },
                  },
                },
              ],
            },
          ],
        },
      });
      jsr.exportState({
        mode: mode,
        running: running,
        remainingSeconds: remaining,
        display: fmt(remaining),
        completedCycles: completedCycles,
        progress: progress,
      });
      return;
    }

    var controls = {
      type: 'row',
      mainAxisAlignment: 'center',
      children: [
        {
          type: 'gestureDetector',
          onTap: 'toggle',
          child: {
            type: 'container',
            decoration: { color: accent(), borderRadius: 24 },
            padding: [18, 10, 18, 10],
            child: {
              type: 'text',
              data: running ? 'Pause' : 'Start',
              style: { color: '#0f172a', fontSize: 16, fontWeight: 'w700' },
            },
          },
        },
        { type: 'sizedBox', width: 12 },
        {
          type: 'gestureDetector',
          onTap: 'reset',
          child: {
            type: 'container',
            decoration: { color: '#334155', borderRadius: 24 },
            padding: [14, 10, 14, 10],
            child: {
              type: 'text',
              data: 'Reset',
              style: { color: '#e2e8f0', fontSize: 14 },
            },
          },
        },
        { type: 'sizedBox', width: 12 },
        {
          type: 'gestureDetector',
          onTap: 'skip',
          child: {
            type: 'text',
            data: 'Skip →',
            style: { color: '#94a3b8', fontSize: 14 },
          },
        },
      ],
    };

    jsr.render({
      // A scrollable root: hosts embed widgets at ANY height (app panels,
      // landing cards) — a fixed column overflows small viewports with
      // RenderFlex stripes instead of scrolling.
      type: 'listView',
      shrinkWrap: false,
      padding: [16, 16, 16, 16],
      children: [
          {
            type: 'row',
            mainAxisAlignment: 'spaceBetween',
            children: [
              {
                type: 'text',
                data: mode === 'focus' ? 'FOCUS' : 'BREAK',
                style: {
                  color: '#94a3b8',
                  fontSize: 12,
                  fontWeight: 'w600',
                },
              },
              {
                type: 'row',
                mainAxisSize: 'min',
                crossAxisAlignment: 'center',
                children: [
                  { type: 'svg', data: FLAG_ICON, size: 13 },
                  { type: 'sizedBox', width: 5 },
                  {
                    type: 'text',
                    data: String(completedCycles),
                    style: { color: '#64748b', fontSize: 12 },
                  },
                ],
              },
            ],
          },
          { type: 'sizedBox', height: 8 },
          {
            type: 'linearProgressIndicator',
            value: progress,
            backgroundColor: '#1e293b',
            color: timeColor,
            minHeight: 6,
            borderRadius: 3,
          },
          { type: 'sizedBox', height: 12 },
          {
            type: 'animatedOpacity',
            opacity: 1.0,
            duration: 150,
            child: {
              type: 'text',
              data: fmt(remaining),
              style: {
                color: timeColor,
                fontSize: 48,
                fontWeight: 'w700',
                textAlign: 'center',
              },
            },
          },
          { type: 'sizedBox', height: 12 },
          controls,
        ],
    });

    jsr.exportState({
      mode: mode,
      running: running,
      remainingSeconds: remaining,
      display: fmt(remaining),
      completedCycles: completedCycles,
      progress: progress,
    });
  }

  jsr.onEvent(handleEvent);
  if (jsr.onViewport) {
    jsr.onViewport(function (v) {
      viewport = v;
      render();
    });
  }
  jsr.setTitle('Focus Timer');
  render();
})();
