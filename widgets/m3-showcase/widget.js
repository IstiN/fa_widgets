// M3 Showcase — Material 3 components rendered from one JSON tree.
// Demonstrates the M3 node types: appBar, banner, searchBar,
// segmentedButton, radio, buttons + tooltip, popupMenu, tabBar, fab,
// navigationBar. All state lives in JS; every control re-renders via
// jsr.render. All colors from jsr.theme.
(function() {
  var state = {
    banner: true,
    nav: 0,
    rail: 0,
    seg: 'week',
    radio: 'standard',
    created: 0,
    lastMenu: null,
    overlay: null // null | 'sheet' | 'dialog' | 'snack' | 'date' | 'time'
  };

  var SEGMENTS = ['day', 'week', 'month'];

  function caption(t, text) {
    return { type: 'padding', padding: [0, 0, 0, 6], child: {
      type: 'text', data: text,
      style: { color: t.muted, fontSize: 11, fontWeight: 'w600', letterSpacing: 1.0 }
    } };
  }

  function card(t, children) {
    return { type: 'container', margin: [0, 0, 0, 14], padding: [12, 12, 12, 12],
      decoration: { color: t.surface, borderRadius: 14, border: { color: t.border } },
      child: { type: 'column', crossAxisAlignment: 'stretch', mainAxisSize: 'min',
        children: children } };
  }

  function drawerNode(t) {
    function item(icon, label, payload) {
      return {
        type: 'listTile',
        leading: { type: 'icon', icon: icon, color: t.muted },
        title: label,
        dense: true,
        onTap: 'drawer_item',
        payload: { value: payload }
      };
    }
    return {
      type: 'container',
      color: t.surface,
      child: {
        type: 'column',
        crossAxisAlignment: 'stretch',
        children: [
          { type: 'padding', padding: [16, 20, 16, 8], child: {
            type: 'text', data: '🧩 M3 Showcase',
            style: { color: t.text, fontSize: 16, fontWeight: 'w700' }
          } },
          { type: 'divider', color: t.border },
          item('home', 'Home', 'home'),
          item('widgets', 'Components', 'components'),
          item('info', 'About', 'about'),
          { type: 'divider', color: t.border },
          item('refresh', 'Reset demo', 'reset')
        ]
      }
    };
  }

  function overlayNode(t) {
    if (state.overlay === 'sheet') {
      return {
        type: 'bottomSheet',
        color: t.surface,
        onDismiss: 'overlay_dismiss',
        child: {
          type: 'container',
          padding: [20, 20, 20, 20],
          child: {
            type: 'column',
            mainAxisSize: 'min',
            crossAxisAlignment: 'stretch',
            children: [
              { type: 'text', data: 'Modal bottom sheet', style: { color: t.text, fontSize: 16, fontWeight: 'w700' } },
              { type: 'sizedBox', height: 8 },
              { type: 'text', data: 'Drag down or tap outside to dismiss — JS gets onDismiss.', style: { color: t.muted, fontSize: 12 } },
              { type: 'sizedBox', height: 12 },
              { type: 'button', text: 'Close from JS', onTap: 'overlay_dismiss' }
            ]
          }
        }
      };
    }
    if (state.overlay === 'dialog') {
      return {
        type: 'dialog',
        title: 'AlertDialog',
        message: 'Actions pop the dialog and fire their event.',
        onDismiss: 'overlay_dismiss',
        actions: [
          { label: 'CANCEL', onTap: 'overlay_dismiss' },
          { label: 'OK', onTap: 'overlay_dismiss' }
        ]
      };
    }
    if (state.overlay === 'snack') {
      return { type: 'snackBar', message: 'Snackbar from a JSON node', actionLabel: 'UNDO', onAction: 'overlay_dismiss' };
    }
    if (state.overlay === 'date') {
      // Pinned initial date keeps the golden frame deterministic (the
      // calendar opens on August 2026 regardless of today's date).
      return { type: 'datePicker', initialDate: '2026-08-19', onSelected: 'date_picked', onDismiss: 'overlay_dismiss' };
    }
    if (state.overlay === 'time') {
      return { type: 'timePicker', initialTime: '09:41', onSelected: 'time_picked', onDismiss: 'overlay_dismiss' };
    }
    return { type: 'sizedBox', height: 0 };
  }

  function render() {
    var t = jsr.theme;
    jsr.exportState({
      nav: state.nav, rail: state.rail, seg: state.seg, radio: state.radio,
      created: state.created, banner: state.banner, lastMenu: state.lastMenu
    });
    jsr.render({
      type: 'drawer',
      drawer: drawerNode(t),
      child: {
      type: 'column',
      crossAxisAlignment: 'stretch',
      children: [
        overlayNode(t),
        {
          type: 'appBar',
          title: 'Material 3',
          color: t.bg,
          // No explicit leading: the drawer node's nested Scaffold makes
          // AppBar show the hamburger automatically.
          actions: [
            { icon: 'refresh', tooltip: 'Reset', onTap: 'reset' }
          ]
        },
        state.banner ? {
          type: 'banner',
          message: 'Every component on this page is a JSON node from JS.',
          icon: 'info',
          actions: [{ label: 'GOT IT', onTap: 'banner_dismiss' }]
        } : { type: 'sizedBox', height: 0 },
        {
          type: 'expanded',
          child: {
            type: 'scroll',
            padding: [16, 12, 16, 12],
            child: {
              type: 'column',
              crossAxisAlignment: 'stretch',
              children: [
                {
                  type: 'searchBar',
                  hint: 'Search components…',
                  onChanged: 'search_changed'
                },
                { type: 'sizedBox', height: 14 },
                card(t, [
                  caption(t, 'SEGMENTEDBUTTON'),
                  {
                    type: 'segmentedButton',
                    segments: [
                      { value: 'day', label: 'Day' },
                      { value: 'week', label: 'Week' },
                      { value: 'month', label: 'Month' }
                    ],
                    selected: [state.seg],
                    onChanged: 'seg_changed'
                  }
                ]),
                card(t, [
                  caption(t, 'RADIO'),
                  {
                    type: 'row',
                    children: [
                      { type: 'radio', value: 'standard', groupValue: state.radio, label: 'Standard', onChanged: 'radio_changed' },
                      { type: 'sizedBox', width: 8 },
                      { type: 'radio', value: 'compact', groupValue: state.radio, label: 'Compact', onChanged: 'radio_changed' }
                    ]
                  }
                ]),
                card(t, [
                  caption(t, 'BUTTONS · TOOLTIP · POPUPMENU'),
                  {
                    type: 'row',
                    children: [
                      { type: 'button', text: 'Filled', onTap: 'noop' },
                      { type: 'sizedBox', width: 8 },
                      { type: 'outlinedButton', text: 'Outlined', onTap: 'noop' },
                      { type: 'sizedBox', width: 8 },
                      { type: 'textButton', text: 'Text', onTap: 'noop' }
                    ]
                  },
                  { type: 'sizedBox', height: 8 },
                  {
                    type: 'row',
                    children: [
                      {
                        type: 'tooltip',
                        message: 'Starred',
                        child: { type: 'iconButton', icon: 'star', onTap: 'noop' }
                      },
                      { type: 'sizedBox', width: 4 },
                      {
                        type: 'popupMenu',
                        icon: 'more_vert',
                        onSelected: 'menu_selected',
                        items: [
                          { value: 'share', label: 'Share', icon: 'share' },
                          { value: 'download', label: 'Download', icon: 'download' },
                          { value: 'delete', label: 'Delete', icon: 'delete' }
                        ]
                      },
                      { type: 'sizedBox', width: 8 },
                      state.lastMenu ? {
                        type: 'expanded', child: {
                          type: 'text', data: 'last pick: ' + state.lastMenu,
                          style: { color: t.muted, fontSize: 11 }
                        }
                      } : { type: 'sizedBox', height: 0 }
                    ]
                  }
                ]),
                card(t, [
                  caption(t, 'TABBAR'),
                  {
                    type: 'container',
                    height: 150,
                    child: {
                      type: 'tabBar',
                      tabs: ['Overview', 'Specs'],
                      children: [
                        { type: 'padding', padding: [0, 10, 0, 0], child: {
                          type: 'text',
                          data: 'Tabs are a self-contained DefaultTabController — switching needs no JS round trip.',
                          style: { color: t.text, fontSize: 12 }
                        } },
                        { type: 'padding', padding: [0, 10, 0, 0], child: {
                          type: 'text',
                          data: 'renderer → JSON → Material 3 widgets under the host theme.',
                          style: { color: t.muted, fontSize: 12 }
                        } }
                      ]
                    }
                  }
                ]),
                card(t, [
                  caption(t, 'NAVIGATIONRAIL'),
                  {
                    type: 'container',
                    height: 190,
                    child: {
                      type: 'row',
                      children: [
                        {
                          type: 'navigationRail',
                          selectedIndex: state.rail,
                          onChanged: 'rail_changed',
                          destinations: [
                            { icon: 'home', label: 'Home' },
                            { icon: 'favorite', label: 'Favorites' },
                            { icon: 'settings', label: 'Settings' }
                          ]
                        },
                        {
                          type: 'expanded',
                          child: {
                            type: 'center',
                            child: {
                              type: 'text',
                              data: 'Rail destination #' + state.rail + ' — same destinations API as navigationBar.',
                              style: { color: t.muted, fontSize: 12 }
                            }
                          }
                        }
                      ]
                    }
                  }
                ]),
                card(t, [
                  caption(t, 'CAROUSEL'),
                  {
                    type: 'container',
                    height: 150,
                    child: {
                      type: 'carousel',
                      itemExtent: 170,
                      children: [
                        { type: 'container', margin: [0, 4, 0, 4], decoration: { color: t.accent, borderRadius: 14 }, child: { type: 'center', child: { type: 'text', data: 'One', style: { color: t.onAccent, fontSize: 16, fontWeight: 'w700' } } } },
                        { type: 'container', margin: [0, 4, 0, 4], decoration: { color: t.accent2, borderRadius: 14 }, child: { type: 'center', child: { type: 'text', data: 'Two', style: { color: t.onAccent, fontSize: 16, fontWeight: 'w700' } } } },
                        { type: 'container', margin: [0, 4, 0, 4], decoration: { color: t.surfaceAlt, borderRadius: 14, border: { color: t.borderBright } }, child: { type: 'center', child: { type: 'text', data: 'Three', style: { color: t.text, fontSize: 16, fontWeight: 'w700' } } } },
                        { type: 'container', margin: [0, 4, 0, 4], decoration: { color: t.accent, borderRadius: 14 }, child: { type: 'center', child: { type: 'text', data: 'Four', style: { color: t.onAccent, fontSize: 16, fontWeight: 'w700' } } } },
                        { type: 'container', margin: [0, 4, 0, 4], decoration: { color: t.accent2, borderRadius: 14 }, child: { type: 'center', child: { type: 'text', data: 'Five', style: { color: t.onAccent, fontSize: 16, fontWeight: 'w700' } } } }
                      ]
                    }
                  }
                ]),
                card(t, [
                  caption(t, 'BOTTOMAPPBAR'),
                  {
                    type: 'bottomAppBar',
                    color: t.surfaceAlt,
                    height: 48,
                    children: [
                      { type: 'iconButton', icon: 'search', onTap: 'noop' },
                      { type: 'iconButton', icon: 'star', onTap: 'noop' },
                      { type: 'iconButton', icon: 'share', onTap: 'noop' },
                      {
                        type: 'expanded',
                        child: {
                          type: 'text',
                          data: '  BottomAppBar inline — pairs with a fab in a real Scaffold.',
                          style: { color: t.muted, fontSize: 11 }
                        }
                      }
                    ]
                  }
                ]),
                card(t, [
                  caption(t, 'FLOATINGACTIONBUTTON'),
                  {
                    type: 'row',
                    children: [
                      { type: 'fab', icon: 'add', label: 'Create', onTap: 'fab_tap' },
                      { type: 'sizedBox', width: 12 },
                      { type: 'fab', icon: 'remove', mini: true, onTap: 'fab_remove' },
                      { type: 'sizedBox', width: 12 },
                      {
                        type: 'expanded',
                        child: {
                          type: 'text',
                          data: 'Created: ' + state.created,
                          style: { color: t.text, fontSize: 13 }
                        }
                      }
                    ]
                  }
                ]),
                card(t, [
                  caption(t, 'OVERLAYS'),
                  {
                    type: 'row',
                    children: [
                      { type: 'outlinedButton', text: 'Sheet', onTap: 'show_sheet' },
                      { type: 'sizedBox', width: 8 },
                      { type: 'outlinedButton', text: 'Dialog', onTap: 'show_dialog' },
                      { type: 'sizedBox', width: 8 },
                      { type: 'outlinedButton', text: 'Snack', onTap: 'show_snack' }
                    ]
                  },
                  { type: 'sizedBox', height: 8 },
                  {
                    type: 'row',
                    children: [
                      { type: 'outlinedButton', text: 'Date', onTap: 'show_date' },
                      { type: 'sizedBox', width: 8 },
                      { type: 'outlinedButton', text: 'Time', onTap: 'show_time' }
                    ]
                  }
                ])
              ]
            }
          }
        },
        {
          type: 'navigationBar',
          selectedIndex: state.nav,
          onChanged: 'nav_changed',
          destinations: [
            { icon: 'home', label: 'Home' },
            { icon: 'star', label: 'Favorites' },
            { icon: 'settings', label: 'Settings' }
          ]
        }
      ]
      }
    });
  }

  function cycle(list, current) {
    var i = list.indexOf(current);
    return list[(i + 1) % list.length];
  }

  jsr.onEvent(function(name, payload) {
    if (name === 'banner_dismiss') state.banner = false;
    if (name === 'reset') {
      state.banner = true; state.nav = 0; state.seg = 'week';
      state.radio = 'standard'; state.created = 0; state.lastMenu = null;
    }
    if (name === 'fab_tap') state.created += 1;
    if (name === 'fab_remove' && state.created > 0) state.created -= 1;
    if (name === 'nav_changed') {
      state.nav = payload && typeof payload.value === 'number'
        ? payload.value
        : (state.nav + 1) % 3;
    }
    if (name === 'rail_changed') {
      state.rail = payload && typeof payload.value === 'number'
        ? payload.value
        : (state.rail + 1) % 3;
    }
    if (name === 'drawer_item') {
      var pick = payload && payload.value ? String(payload.value) : null;
      if (pick === 'reset') {
        state.banner = true; state.nav = 0; state.rail = 0; state.seg = 'week';
        state.radio = 'standard'; state.created = 0; state.lastMenu = null;
      } else if (pick) {
        state.lastMenu = 'drawer: ' + pick;
      }
    }
    if (name === 'seg_changed') {
      state.seg = payload && typeof payload.value === 'string'
        ? payload.value
        : cycle(SEGMENTS, state.seg);
    }
    if (name === 'radio_changed') {
      state.radio = payload && typeof payload.value === 'string'
        ? payload.value
        : (state.radio === 'standard' ? 'compact' : 'standard');
    }
    if (name === 'menu_selected') {
      state.lastMenu = payload && payload.value ? String(payload.value) : null;
    }
    if (name === 'show_sheet') state.overlay = 'sheet';
    if (name === 'show_dialog') state.overlay = 'dialog';
    if (name === 'show_snack') state.overlay = 'snack';
    if (name === 'show_date') state.overlay = 'date';
    if (name === 'show_time') state.overlay = 'time';
    if (name === 'overlay_dismiss') state.overlay = null;
    if (name === 'date_picked' || name === 'time_picked') state.overlay = null;
    render();
  });

  jsr.setTitle('🧩 M3 Showcase');
  render();
})();
