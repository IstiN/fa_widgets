// Video Player — `video` node backed by the host JsMediaHost (video_player
// in the demo app). Cinematic dark design: hero card with gradient overlay,
// SVG source cards and BoxFit selector. The node's built-in transport
// controls stay enabled (controls: true).
(function() {
  var VIDEOS = [
    {
      title: 'Big Buck Bunny',
      meta: 'Blender Foundation · 9:56 · 1080p',
      url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      icon: 'bunny'
    },
    {
      title: 'Elephants Dream',
      meta: 'Orange Open Movie · 10:53 · 1080p',
      url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      icon: 'elephant'
    },
    {
      title: 'Sintel',
      meta: 'Blender Foundation · 14:48 · 4K',
      url: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
      icon: 'flame'
    }
  ];
  var FITS = ['contain', 'cover', 'fill'];

  // ── Stylish inline SVG icons (24×24, stroke-based) ──────────────────────
  function svgIcon(body, size, color) {
    return {
      type: 'svg',
      data: '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" ' +
        'fill="none" stroke="' + color + '" stroke-width="1.8" ' +
        'stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>',
      width: size, height: size
    };
  }
  var ICONS = {
    // Film strip — section headers.
    film: '<rect x="2.5" y="4" width="19" height="16" rx="2.5"/>' +
      '<path d="M7.5 4 v16 M16.5 4 v16 M2.5 9 h5 M2.5 15 h5 M16.5 9 h5 M16.5 15 h5"/>',
    // Bunny ears + head (Big Buck Bunny).
    bunny: '<path d="M9.2 9.5 C8 4.5 7 2.2 8.4 2.2 C9.8 2.2 10.2 6 10.8 8.6"/>' +
      '<path d="M14.8 9.5 C16 4.5 17 2.2 15.6 2.2 C14.2 2.2 13.8 6 13.2 8.6"/>' +
      '<circle cx="12" cy="15.5" r="5.5"/><path d="M10 15 h.01 M14 15 h.01"/>',
    // Elephant head + ears + trunk (Elephants Dream).
    elephant: '<circle cx="12" cy="9.5" r="5.5"/>' +
      '<circle cx="5.6" cy="9.5" r="2.6"/><circle cx="18.4" cy="9.5" r="2.6"/>' +
      '<path d="M12 15 v3 a2.5 2.5 0 0 0 2.5 2.5"/>',
    // Flame (Sintel — the dragon).
    flame: '<path d="M12 2.5 C12 2.5 6.5 8.5 6.5 13.5 a5.5 5.5 0 0 0 11 0 ' +
      'C17.5 8.5 12 2.5 12 2.5 Z"/>' +
      '<path d="M12 21 a2.8 2.8 0 0 1 -2.8-2.8 c0-1.8 2.8-3.7 2.8-3.7 s2.8 1.9 2.8 3.7 A2.8 2.8 0 0 1 12 21 Z"/>',
    // BoxFit glyphs: framed content.
    contain: '<rect x="3" y="3" width="18" height="18" rx="2.5"/>' +
      '<rect x="8" y="8" width="8" height="8" rx="1.5"/>',
    cover: '<rect x="3" y="3" width="18" height="18" rx="2.5"/>' +
      '<path d="M6.5 3 v18 M17.5 3 v18" stroke-dasharray="2.5 2.5"/>' +
      '<rect x="6.5" y="6" width="11" height="12" rx="1.5"/>',
    fill: '<rect x="3" y="3" width="18" height="18" rx="2.5"/>' +
      '<path d="M7 12 h10 M7 12 l2.2 -2.2 M7 12 l2.2 2.2 M17 12 l-2.2 -2.2 M17 12 l-2.2 2.2"/>',
    check: '<circle cx="12" cy="12" r="9"/><path d="M8 12.5 l2.8 2.8 L16.5 9.5"/>',
    aspect: '<rect x="2.5" y="5" width="19" height="14" rx="2.5"/>' +
      '<path d="M2.5 9.5 h19"/>'
  };

  var state = { video: 0, fit: 'contain' };

  // '#rrggbb' + alpha suffix → Flutter '#aarrggbb'.
  function alpha(hex, a) {
    return a + hex.substring(1);
  }

  function sectionHeader(iconBody, label) {
    var t = jsr.theme;
    return {
      type: 'row',
      crossAxisAlignment: 'center',
      children: [
        svgIcon(iconBody, 14, t.accent),
        { type: 'sizedBox', width: 7 },
        {
          type: 'text', data: label,
          style: { color: t.muted, fontSize: 11, fontWeight: 'w700', letterSpacing: 2.2 }
        }
      ]
    };
  }

  function sourceCard(v, i) {
    var t = jsr.theme;
    var selected = state.video === i;
    var iconColor = selected ? t.onAccent : t.accent;
    return {
      type: 'inkWell',
      onTap: 'select_video',
      payload: { value: String(i) },
      borderRadius: 14,
      child: {
        type: 'container',
        padding: [10, 12, 10, 12],
        decoration: {
          color: selected ? alpha(t.accent, '#1F') : t.surface,
          borderRadius: 14,
          borderColor: selected ? t.accent : t.border,
          borderWidth: selected ? 1.5 : 1
        },
        child: {
          type: 'row',
          crossAxisAlignment: 'center',
          children: [
            {
              type: 'container',
              width: 38, height: 38,
              decoration: {
                color: selected ? t.accent : alpha(t.accent, '#1A'),
                borderRadius: 11
              },
              child: { type: 'center', child: svgIcon(ICONS[v.icon], 21, iconColor) }
            },
            { type: 'sizedBox', width: 12 },
            {
              type: 'expanded',
              child: {
                type: 'column',
                crossAxisAlignment: 'start',
                children: [
                  {
                    type: 'text', data: v.title,
                    style: {
                      color: t.text, fontSize: 14,
                      fontWeight: selected ? 'w700' : 'w600'
                    }
                  },
                  { type: 'sizedBox', height: 2 },
                  {
                    type: 'text', data: v.meta,
                    style: { color: t.muted, fontSize: 11 }
                  }
                ]
              }
            },
            selected ? svgIcon(ICONS.check, 20, t.accent) : { type: 'sizedBox', width: 20 }
          ]
        }
      }
    };
  }

  function fitChip(f) {
    var t = jsr.theme;
    var selected = state.fit === f;
    var fg = selected ? t.onAccent : t.muted;
    return {
      type: 'expanded',
      child: {
        type: 'inkWell',
        onTap: 'select_fit',
        payload: { value: f },
        borderRadius: 12,
        child: {
          type: 'container',
          padding: [9, 6, 9, 6],
          decoration: {
            color: selected ? t.accent : t.surface,
            borderRadius: 12,
            borderColor: selected ? t.accent : t.border,
            borderWidth: 1
          },
          child: {
            type: 'row',
            mainAxisAlignment: 'center',
            crossAxisAlignment: 'center',
            children: [
              svgIcon(ICONS[f], 16, fg),
              { type: 'sizedBox', width: 6 },
              {
                type: 'text', data: f,
                style: { color: fg, fontSize: 12, fontWeight: 'w600' }
              }
            ]
          }
        }
      }
    };
  }

  function heroCard() {
    var t = jsr.theme;
    var v = VIDEOS[state.video];
    return {
      type: 'container',
      decoration: {
        color: '#000000',
        borderRadius: 18,
        borderColor: t.border,
        borderWidth: 1,
        shadows: [
          { color: alpha('#000000', '#59'), blur: 24, offsetY: 10 }
        ]
      },
      clip: true,
      child: {
        type: 'stack',
        children: [
          {
            // Fluid width, fixed 16:9 ratio — no hardcoded pixel size.
            type: 'aspectRatio', aspectRatio: 1.78,
            child: {
              type: 'video',
              src: v.url,
              controls: true,
              autoPlay: false,
              fit: state.fit
            }
          },
          {
            // Bottom gradient title bar.
            positioned: { left: 0, right: 0, bottom: 0 },
            child: {
              type: 'container',
              padding: [26, 14, 10, 14],
              decoration: {
                gradient: {
                  type: 'linear',
                  begin: 'topCenter', end: 'bottomCenter',
                  colors: ['#00000000', alpha('#000000', '#D9')]
                }
              },
              child: {
                type: 'row',
                crossAxisAlignment: 'center',
                children: [
                  svgIcon(ICONS[v.icon], 15, '#FFFFFF'),
                  { type: 'sizedBox', width: 7 },
                  {
                    type: 'expanded',
                    child: {
                      type: 'text', data: v.title,
                      style: {
                        color: '#FFFFFF', fontSize: 14, fontWeight: 'w700',
                        shadows: [{ color: alpha('#000000', '#8C'), blur: 6 }]
                      }
                    }
                  },
                  {
                    type: 'text', data: '16:9',
                    style: { color: alpha('#FFFFFF', '#8C'), fontSize: 10, fontWeight: 'w600', letterSpacing: 1.2 }
                  }
                ]
              }
            }
          }
        ]
      }
    };
  }

  function render() {
    var t = jsr.theme;
    jsr.exportState({ video: state.video, title: VIDEOS[state.video].title, fit: state.fit });
    jsr.render({
      type: 'container',
      color: t.bg,
      child: {
        type: 'listView', shrinkWrap: false, padding: [16, 16, 16, 24],
        children: [
          heroCard(),
          { type: 'sizedBox', height: 18 },
          sectionHeader(ICONS.film, 'SOURCE'),
          { type: 'sizedBox', height: 8 },
          sourceCard(VIDEOS[0], 0),
          { type: 'sizedBox', height: 8 },
          sourceCard(VIDEOS[1], 1),
          { type: 'sizedBox', height: 8 },
          sourceCard(VIDEOS[2], 2),
          { type: 'sizedBox', height: 18 },
          sectionHeader(ICONS.aspect, 'FIT'),
          { type: 'sizedBox', height: 8 },
          {
            type: 'row',
            children: [
              fitChip('contain'),
              { type: 'sizedBox', width: 8 },
              fitChip('cover'),
              { type: 'sizedBox', width: 8 },
              fitChip('fill')
            ]
          }
        ]
      }
    });
  }

  jsr.onEvent(function(name, payload) {
    var value = payload && payload.value;
    if (name === 'select_video') {
      // Payload may be a scalar or a single-element list.
      var v = value instanceof Array ? value[0] : value;
      state.video = Math.max(0, Math.min(VIDEOS.length - 1, parseInt(v, 10) || 0));
    }
    if (name === 'select_fit') {
      var f = value instanceof Array ? value[0] : value;
      if (FITS.indexOf(f) >= 0) state.fit = f;
    }
    render();
  });

  jsr.setTitle('🎬 Video Player');
  render();
})();
