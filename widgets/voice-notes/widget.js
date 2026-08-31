// Voice Notes widget — microphone capture + speech-to-text via the
// jsr.fa.asr bridge. Record/Stop toggle (jsr.fa.asr.stop) → the take is
// saved with its audio (playable via an audio node) and its transcript
// appended to a persisted list (jsr.storage). A take survives a failed
// or unavailable transcription — the audio is the primary artifact.
(function() {
  var t = jsr.theme;
  var notes = []; // [{ text, url, seconds, createdMs }]
  var busy = null; // null | 'recording' | 'transcribing'
  var error = null; // null | { kind: 'permission'|'error', message }
  var maxRecordSeconds = 120; // override via jsr.storage 'maxRecordSeconds'

  function fail(msg) {
    busy = null;
    error = {
      kind: msg.indexOf('permission') >= 0 ? 'permission' : 'error',
      message: msg,
    };
  }

  function persist() {
    jsr.storage.set('notes', notes);
  }

  function stopRecording() {
    if (busy !== 'recording') return;
    // The pending record() promise resolves with the take so far. Older
    // hosts without asr.stop simply run out the max-seconds guard.
    if (jsr.fa.asr.stop) jsr.fa.asr.stop();
  }

  function startRecording() {
    if (busy) return;
    busy = 'recording';
    error = null;
    render();
    jsr.fa.asr.record({ seconds: maxRecordSeconds }).then(function(rec) {
      if (rec && rec.__error) {
        fail(String(rec.__error));
        render();
        return;
      }
      busy = 'transcribing';
      render();
      jsr.fa.asr.transcribe({ path: rec.path }).then(function(result) {
        busy = null;
        var text = (result && !result.__error && result.text) || '';
        // The audio is saved either way — a missing/failed transcript
        // (e.g. no endpoint configured, or the web preview stub) must
        // not throw the take away.
        notes.unshift({
          text: text,
          url: rec.path || '',
          seconds: Math.round((rec.durationMs || 0) / 1000),
          createdMs: Date.now(),
        });
        persist();
        render();
      }, function(e) {
        busy = null;
        notes.unshift({
          text: '',
          url: rec.path || '',
          seconds: Math.round((rec.durationMs || 0) / 1000),
          createdMs: Date.now(),
        });
        persist();
        render();
      });
    }, function(e) {
      fail(String(e));
      render();
    });
  }

  function fmtTime(ms) {
    var d = new Date(ms);
    var h = ('0' + d.getHours()).slice(-2);
    var m = ('0' + d.getMinutes()).slice(-2);
    return h + ':' + m;
  }

  function noteRow(note) {
    var body = [];
    if (note.url) {
      body.push({ type: 'audio', src: note.url });
      body.push({ type: 'sizedBox', height: 6 });
    }
    body.push({ type: 'text',
      data: note.text || '(no transcript)',
      style: { color: note.text ? t.text : t.muted, fontSize: 14 } });
    body.push({ type: 'sizedBox', height: 4 });
    body.push({ type: 'text',
      data: fmtTime(note.createdMs) + '  ·  ' + note.seconds + ' s',
      style: { color: t.muted, fontSize: 11 } });
    return {
      type: 'container',
      margin: [16, 0, 16, 8],
      padding: [12, 12, 12, 12],
      decoration: {
        color: t.surface, borderRadius: 12,
        border: { color: t.border, width: 1 },
      },
      child: { type: 'row', crossAxisAlignment: 'start', children: [
        { type: 'container',
          width: 4, height: 40,
          margin: [0, 0, 10, 0],
          decoration: { color: t.accent, borderRadius: 2 },
        },
        { type: 'expanded', child: {
          type: 'column', crossAxisAlignment: 'start', children: body } },
      ] },
    };
  }

  function recordCard() {
    var isRecording = busy === 'recording';
    return {
      type: 'padding', padding: [16, 16, 16, 12], child: {
        type: 'container',
        padding: [16, 16, 16, 16],
        decoration: {
          color: t.surface, borderRadius: 12,
          border: { color: isRecording ? '#ef4444' : t.border, width: 1 },
        },
        child: { type: 'column', crossAxisAlignment: 'center', children: [
          { type: 'icon', name: 'mic',
            color: isRecording ? '#ef4444' : t.accent, size: 36 },
          { type: 'sizedBox', height: 8 },
          { type: 'text',
            data: isRecording
              ? 'Recording… (max ' + maxRecordSeconds + ' s)'
              : busy === 'transcribing'
                ? 'Transcribing…'
                : 'Tap Record, tap Stop when done',
            style: { color: t.text, fontSize: 14, fontWeight: 'w600',
              textAlign: 'center' } },
          { type: 'sizedBox', height: 10 },
          busy === 'transcribing'
            ? { type: 'circularProgressIndicator', size: 22 }
            : { type: 'button',
                label: isRecording ? 'Stop' : 'Record',
                onPressed: 'record_toggle',
                color: isRecording ? '#ef4444' : t.accent },
        ] },
      },
    };
  }

  function errorCard() {
    var isPerm = error.kind === 'permission';
    return {
      type: 'padding', padding: [16, 0, 16, 12], child: {
        type: 'container',
        padding: [16, 16, 16, 16],
        decoration: {
          color: t.surface, borderRadius: 12,
          border: { color: isPerm ? t.accent : '#ef4444', width: 1 },
        },
        child: { type: 'column', crossAxisAlignment: 'center', children: [
          { type: 'icon', name: isPerm ? 'lock' : 'warning',
            color: isPerm ? t.accent : '#ef4444', size: 28 },
          { type: 'sizedBox', height: 8 },
          { type: 'text',
            data: isPerm ? 'Microphone permission needed' : 'Could not record',
            style: { color: t.text, fontSize: 14, fontWeight: 'w600',
              textAlign: 'center' } },
          { type: 'sizedBox', height: 6 },
          { type: 'text',
            data: isPerm
              ? 'Grant the microphone permission: tap the shield icon in ' +
                'this app\'s header and enable "Microphone".'
              : error.message,
            style: { color: t.muted, fontSize: 12, textAlign: 'center' } },
          { type: 'sizedBox', height: 10 },
          { type: 'button', label: 'Retry', onPressed: 'retry',
            color: t.accent },
        ] },
      },
    };
  }

  function emptyState() {
    return {
      type: 'padding', padding: [16, 40, 16, 24], child: {
        type: 'column', crossAxisAlignment: 'center', children: [
          { type: 'icon', name: 'mic_none', color: t.muted, size: 40 },
          { type: 'sizedBox', height: 10 },
          { type: 'text', data: 'No voice notes yet',
            style: { color: t.text, fontSize: 15, fontWeight: 'w600',
              textAlign: 'center' } },
          { type: 'sizedBox', height: 4 },
          { type: 'text',
            data: 'Record a take — audio + transcript land here.',
            style: { color: t.muted, fontSize: 12, textAlign: 'center' } },
        ] },
    };
  }

  function render() {
    jsr.render({
      type: 'column', crossAxisAlignment: 'stretch', children: [
        recordCard(),
        error ? errorCard() : { type: 'sizedBox', height: 0 },
        notes.length
          ? { type: 'padding', padding: [16, 0, 16, 4], child: {
              type: 'row', mainAxisAlignment: 'spaceBetween',
              crossAxisAlignment: 'center', children: [
                { type: 'text',
                  data: notes.length + (notes.length === 1 ? ' note' : ' notes'),
                  style: { color: t.muted, fontSize: 11 } },
                { type: 'textButton', text: 'Clear all', onTap: 'clear_notes' },
              ] } }
          : { type: 'sizedBox', height: 0 },
        notes.length
          ? { type: 'column', crossAxisAlignment: 'stretch',
              children: notes.map(noteRow) }
          : emptyState(),
      ],
    });
    jsr.exportState({
      noteCount: notes.length,
      notes: notes.map(function(n) { return n.text; }),
      busy: busy,
      error: error ? error.message : null,
      maxRecordSeconds: maxRecordSeconds,
    });
  }

  function handleEvent(actionId) {
    if (actionId === 'record_toggle') {
      if (busy === 'recording') {
        stopRecording();
      } else {
        startRecording();
      }
    } else if (actionId === 'retry') {
      error = null;
      render();
    } else if (actionId === 'clear_notes') {
      notes = [];
      persist();
      render();
    }
  }

  jsr.onEvent(handleEvent);
  jsr.onThemeChange(function(theme) { t = theme; render(); });
  jsr.setTitle('Voice Notes');

  // Restore saved notes (and the max-duration override), then boot.
  jsr.storage.get('maxRecordSeconds').then(function(saved) {
    if (typeof saved === 'number' && saved >= 5 && saved <= 600) {
      maxRecordSeconds = saved;
    }
    jsr.storage.get('notes').then(function(savedNotes) {
      if (savedNotes && savedNotes.length) notes = savedNotes;
      render();
    });
  });
})();
