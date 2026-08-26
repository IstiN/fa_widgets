# Contributing

PRs welcome! Everything happens through review: direct pushes to `main` skip
validation only on paper — publish still re-validates and fails loudly.

## Quick start

```sh
git clone git@github.com:IstiN/fa_widgets.git && cd fa_widgets
dart pub get
dart run bin/fa_widgets.dart validate        # must exit 0
dart run bin/fa_widgets.dart catalog --out build/catalog
```

## Authoring checklist

- [ ] Folder `widgets/<id>/`, lowercase-hyphen id == folder name.
- [ ] `manifest.json` per `docs/schema.md`; bump `version` on every change.
- [ ] `widget.js` renders through `jsr.render`, registers `jsr.onEvent`,
      calls `jsr.exportState` (so agent snapshots stay useful).
- [ ] Works on dark theme (hardcoded palettes like the samples are fine,
      or read `jsr.theme`).
- [ ] Declare honestly what you use: `network: true`, `allowedCommands`,
      service permission keys (`contacts`, `calendar`, ...). Undeclared
      capability use = rejected. All permissions are runtime-gated anyway.
- [ ] Icon `icon.svg` present, legible at small sizes on dark backgrounds.

## Code style

Tooling (this package): single quotes, package-relative imports, keep files
small, `dart analyze`/`dart test` green. Widgets: plain ES2019-compatible JS
(no imports/bare specifiers — multi-file needs go through relative inlining
per the js_widget_runtime loader), no external CDNs unless `network: true`.

## Releasing

Nothing manual: merge to `main` rebuilds the rolling `catalog` release and
tags any bumped widget versions.
