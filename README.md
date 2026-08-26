# fa_widgets

The Fa widget catalog: a curated collection of JavaScript widgets for the
[Fa app](https://fa1.dev) and its agent. Widgets are small apps written
against [`js_widget_runtime`](https://pub.dev/packages/js_widget_runtime) —
a `jsr`-object API rendered as native Flutter UI (JSON UI tree + event
handler), running inside Fa's own JS engine with per-permission gating
(network, commands, system services — all default denied).

This repo holds **sources only**. Release artifacts (per-widget zips +
`catalog.json`) are built by CI and published to a rolling GitHub release:

```
https://github.com/IstiN/fa_widgets/releases/latest/download/catalog.json
https://github.com/IstiN/fa_widgets/releases/latest/download/<id>-<version>.zip
```

Version-bumped widgets also get immutable tags `<id>-v<version>` with the zip
attached — stable permalinks and rollback points.

## Layout

```
widgets/<id>/            one folder per widget: manifest.json + widget.js + icon.svg + assets
lib/, bin/, test/        the Dart tooling that validates and packages the catalog
docs/                    schema notes
.github/workflows/       validate.yml (PRs) · publish.yml (rolling release)
```

## Contributing a widget

1. Fork / branch, add `widgets/my-widget/`:
   - `manifest.json` — see `docs/schema.md` (id == folder name, semver,
     declared permissions).
   - `widget.js` — an IIFE using the `jsr` API (`jsr.render`,
     `jsr.onEvent`, `jsr.exportState`, ...). Look at `calculator` and
     `focus-timer` for reference patterns.
   - `icon.svg` — recommended, square, works on dark backgrounds.
2. Run locally:
   ```
   dart pub get
   dart run bin/fa_widgets.dart validate
   dart run bin/fa_widgets.dart catalog --out build/catalog   # optional dry run
   ```
3. Open a PR — CI validates. On merge to `main` the catalog release is
   rebuilt automatically; your widget appears in Fa's Plugins gallery and on
   https://fa1.dev/widgets without any further steps.

Bump `version` in the manifest for every change of content — CI detects bumps
and cuts per-widget release tags.

## For maintainers

Publishing is fully automated on push to `main`
(`.github/workflows/publish.yml`): validate → build zips → diff against the
current published catalog → tag bumped widgets → refresh the rolling
`catalog` release with `--clobber`. Requires only the default `GITHUB_TOKEN`.

## License

MIT — see [LICENSE](LICENSE).
