// 3D Model Viewer — interactive GLB/GLTF demo on jsr.scene3d. Premium
// control-room design: header with status pill, radial-gradient scene card,
// SVG control bar. Scene expands to whatever height the host allots.
(function() {
  'use strict';

  var modelUrl = 'https://modelviewer.dev/shared-assets/models/Astronaut.glb';

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
    // Isometric cube.
    cube: '<path d="M12 2.5 L21 7.2 V16.8 L12 21.5 L3 16.8 V7.2 Z"/>' +
      '<path d="M3 7.2 L12 12 L21 7.2 M12 12 V21.5"/>',
    // Download into tray.
    load: '<path d="M12 3.5 V14 M7.5 9.8 L12 14.3 L16.5 9.8"/>' +
      '<path d="M4 16.5 V18.5 A2 2 0 0 0 6 20.5 H18 A2 2 0 0 0 20 18.5 V16.5"/>',
    // Rotate clockwise.
    rotate: '<path d="M20.5 12 a8.5 8.5 0 1 1 -2.5 -6"/>' +
      '<path d="M20.5 3.5 V8 H16"/>',
    // Rotate counter-clockwise (reset).
    reset: '<path d="M3.5 12 a8.5 8.5 0 1 0 2.5 -6"/>' +
      '<path d="M3.5 3.5 V8 H8"/>',
    // Orbit hint: dotted ellipse + dot.
    orbit: '<ellipse cx="12" cy="12" rx="9.5" ry="4" stroke-dasharray="2.5 3"/>' +
      '<circle cx="12" cy="12" r="2.6"/>'
  };

  var loaded = false;
  var rotation = [0, 0, 0];

  // '#rrggbb' + alpha suffix → Flutter '#aarrggbb'.
  function alpha(hex, a) {
    return a + hex.substring(1);
  }

  function statusPill() {
    var t = jsr.theme;
    var fg = loaded ? t.accent : t.muted;
    return {
      type: 'container',
      padding: [5, 10, 5, 10],
      decoration: {
        color: alpha(loaded ? t.accent : t.muted, '#1A'),
        borderRadius: 20,
        borderColor: alpha(fg, '#59'),
        borderWidth: 1
      },
      child: {
        type: 'row',
        crossAxisAlignment: 'center',
        children: [
          {
            type: 'container',
            width: 7, height: 7,
            decoration: { color: fg, borderRadius: 4 }
          },
          { type: 'sizedBox', width: 6 },
          {
            type: 'text', data: loaded ? 'LOADED' : 'IDLE',
            style: { color: fg, fontSize: 10, fontWeight: 'w700', letterSpacing: 1.6 }
          }
        ]
      }
    };
  }

  function header() {
    var t = jsr.theme;
    return {
      type: 'container',
      padding: [12, 14, 12, 14],
      decoration: {
        color: t.surface,
        borderRadius: 16,
        borderColor: t.border,
        borderWidth: 1
      },
      child: {
        type: 'row',
        crossAxisAlignment: 'center',
        children: [
          {
            type: 'container',
            width: 42, height: 42,
            decoration: {
              gradient: {
                type: 'linear',
                begin: 'topLeft', end: 'bottomRight',
                colors: [t.accent, t.accent2]
              },
              borderRadius: 13,
              shadows: [{ color: alpha(t.accent, '#4D'), blur: 12, offsetY: 4 }]
            },
            child: { type: 'center', child: svgIcon(ICONS.cube, 23, t.onAccent) }
          },
          { type: 'sizedBox', width: 12 },
          {
            type: 'expanded',
            child: {
              type: 'column',
              crossAxisAlignment: 'start',
              children: [
                {
                  type: 'text', data: '3D Model Viewer',
                  style: { color: t.text, fontSize: 16, fontWeight: 'w700' }
                },
                { type: 'sizedBox', height: 2 },
                {
                  type: 'text', data: 'Astronaut.glb · glTF · PBR',
                  style: { color: t.muted, fontSize: 11 }
                }
              ]
            }
          },
          statusPill()
        ]
      }
    };
  }

  function sceneCard() {
    var t = jsr.theme;
    return {
      type: 'expanded',
      child: {
        type: 'container',
        decoration: {
          borderRadius: 18,
          borderColor: t.border,
          borderWidth: 1,
          gradient: {
            type: 'radial',
            center: 'center', radius: 1.1,
            colors: [t.surfaceAlt, t.bg]
          },
          shadows: [{ color: alpha('#000000', '#40'), blur: 20, offsetY: 8 }]
        },
        clip: true,
        child: {
          type: 'stack',
          fit: 'expand',
          children: [
            { type: 'scene3d', id: 'main' },
            {
              positioned: { left: 0, right: 0, bottom: 10 },
              child: {
                type: 'center',
                child: {
                  type: 'container',
                  padding: [5, 12, 5, 12],
                  decoration: {
                    color: alpha(t.bg, '#B3'),
                    borderRadius: 16,
                    borderColor: t.border,
                    borderWidth: 1
                  },
                  child: {
                    type: 'row',
                    mainAxisSize: 'min',
                    crossAxisAlignment: 'center',
                    children: [
                      svgIcon(ICONS.orbit, 13, t.muted),
                      { type: 'sizedBox', width: 6 },
                      {
                        type: 'text',
                        data: loaded ? 'scene3d · astronaut' : 'press LOAD to fetch the model',
                        style: { color: t.muted, fontSize: 10.5, letterSpacing: 0.4 }
                      }
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    };
  }

  function controlButton(iconBody, label, action, enabled) {
    var t = jsr.theme;
    var primary = action === 'load' && !loaded;
    var fg = !enabled ? alpha(t.muted, '#80')
      : primary ? t.onAccent
      : t.accent;
    return {
      type: 'expanded',
      child: {
        type: 'inkWell',
        onTap: action,
        borderRadius: 13,
        child: {
          type: 'container',
          padding: [11, 6, 11, 6],
          decoration: {
            color: !enabled ? t.surface
              : primary ? t.accent
              : alpha(t.accent, '#14'),
            borderRadius: 13,
            borderColor: !enabled ? t.border : primary ? t.accent : alpha(t.accent, '#59'),
            borderWidth: 1,
            shadows: primary
              ? [{ color: alpha(t.accent, '#4D'), blur: 14, offsetY: 5 }]
              : null
          },
          child: {
            type: 'row',
            mainAxisAlignment: 'center',
            crossAxisAlignment: 'center',
            children: [
              svgIcon(iconBody, 16, fg),
              { type: 'sizedBox', width: 7 },
              {
                type: 'text', data: label,
                style: { color: fg, fontSize: 12.5, fontWeight: 'w700', letterSpacing: 0.6 }
              }
            ]
          }
        }
      }
    };
  }

  function buildUI() {
    var t = jsr.theme;
    return {
      type: 'container',
      color: t.bg,
      padding: [14, 14, 16, 14],
      child: {
        type: 'column',
        children: [
          header(),
          { type: 'sizedBox', height: 12 },
          sceneCard(),
          { type: 'sizedBox', height: 12 },
          {
            type: 'row',
            children: [
              controlButton(ICONS.load, loaded ? 'RELOAD' : 'LOAD', 'load', true),
              { type: 'sizedBox', width: 8 },
              controlButton(ICONS.rotate, 'ROTATE', 'rotate', loaded),
              { type: 'sizedBox', width: 8 },
              controlButton(ICONS.reset, 'RESET', 'reset', loaded)
            ]
          }
        ]
      }
    };
  }

  jsr.onEvent(function(actionId) {
    if (actionId === 'load') {
      loaded = true;
      jsr.scene3d.create('main', {
        camera: { position: [0, 0, 3], target: [0, 0, 0] }
      });
      jsr.scene3d.addModel('main', {
        id: 'astronaut',
        src: modelUrl
      });
    } else if (actionId === 'rotate' && loaded) {
      rotation = [45, 45, 0];
      jsr.scene3d.setTransform('main', 'astronaut', {
        rotation: rotation
      });
    } else if (actionId === 'reset' && loaded) {
      rotation = [0, 0, 0];
      jsr.scene3d.setTransform('main', 'astronaut', {
        rotation: rotation
      });
    }
    jsr.exportState({ loaded: loaded, rotation: rotation });
    jsr.render(buildUI());
  });

  jsr.render(buildUI());
  jsr.exportState({ loaded: loaded, rotation: rotation });
})();
