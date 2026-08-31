// Adaptive Dashboard — reference for the adaptive-layout toolkit:
// - `adaptive` NODE: renderer picks a subtree by the ALLOTTED width
//   (LayoutBuilder — works for tiles/panels/full screen, no JS round trip)
// - `gridView.maxCrossAxisExtent`: columns float with width
// - `jsr.breakpoint()` / `jsr.adaptive()`: JS-side values (padding, labels)
// - `jsr.onViewport`: re-render when the host size changes
(function() {
  var STATS = [
    { icon: '📈', label: 'Revenue', value: '$12.4k', delta: '+8.1%' },
    { icon: '👥', label: 'Users', value: '3,842', delta: '+2.4%' },
    { icon: '🛒', label: 'Orders', value: '512', delta: '-1.2%' },
    { icon: '⏱️', label: 'Avg. session', value: '4m 32s', delta: '+12s' },
    { icon: '🌍', label: 'Countries', value: '27', delta: '+3' },
    { icon: '⭐', label: 'Rating', value: '4.8', delta: '+0.1' }
  ];

  var viewport = null;

  function statCard(t, s) {
    return {
      type: 'card', color: t.surface,
      child: {
        type: 'container', padding: 14,
        child: {
          type: 'column', crossAxisAlignment: 'start', mainAxisSize: 'min',
          children: [
            { type: 'text', data: s.icon, style: { fontSize: 22 } },
            { type: 'sizedBox', height: 6 },
            {
              type: 'text', data: s.value,
              style: { color: t.text, fontSize: 20, fontWeight: 'w700' }
            },
            {
              type: 'text', data: s.label + ' · ' + s.delta,
              style: { color: t.muted, fontSize: 11 }
            }
          ]
        }
      }
    };
  }

  function header(t) {
    var bp = jsr.breakpoint();
    var sizeText = viewport
      ? Math.round(viewport.width) + '×' + Math.round(viewport.height)
      : 'unknown';
    return {
      type: 'row',
      children: [
        {
          type: 'expanded',
          child: {
            type: 'column', crossAxisAlignment: 'start', mainAxisSize: 'min',
            children: [
              {
                type: 'text', data: 'Dashboard',
                style: { color: t.text, fontSize: 20, fontWeight: 'w700' }
              },
              {
                type: 'text',
                data: 'breakpoint: ' + bp + ' · viewport: ' + sizeText,
                style: { color: t.muted, fontSize: 11 }
              }
            ]
          }
        },
        {
          type: 'chip', label: bp,
          color: t.accent
        }
      ]
    };
  }

  function render() {
    var t = jsr.theme;
    // jsr.adaptive for VALUES: outer padding breathes with the width.
    var pad = jsr.adaptive({ compact: [12, 12, 12, 20], medium: [20, 16, 20, 24], expanded: [32, 20, 32, 28] }) || [12, 12, 12, 20];
    jsr.exportState({
      breakpoint: jsr.breakpoint(),
      viewport: viewport
    });
    jsr.render({
      type: 'container',
      color: t.bg,
      child: {
        type: 'listView', shrinkWrap: false, padding: pad,
        children: [
          header(t),
          { type: 'sizedBox', height: 12 },
          // The adaptive NODE switches layout by the allotted width —
          // no viewport event needed, it reacts to pure constraints.
          {
            type: 'adaptive',
            compact: {
              type: 'column', mainAxisSize: 'min',
              children: STATS.map(function(s) { return statCard(t, s); })
            },
            medium: {
              type: 'gridView', crossAxisCount: 2,
              crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.9,
              children: STATS.map(function(s) { return statCard(t, s); })
            },
            expanded: {
              // Columns "no wider than 260" — the count floats with width.
              type: 'gridView', maxCrossAxisExtent: 260,
              crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.7,
              children: STATS.map(function(s) { return statCard(t, s); })
            }
          }
        ]
      }
    });
  }

  jsr.onViewport(function(v) {
    viewport = v;
    render();
  });

  jsr.setTitle('📐 Adaptive Dashboard');
  render();
})();
