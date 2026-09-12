# Schema reference

## Three widget kinds

A `widgets/<id>/` folder is one of:

- **LOCAL** — `manifest.json` + `widget.js` (+ assets) all live here.
  Used for widgets calling Fa-specific APIs (`jsr.fa.*`) and conscious
  forks (e.g. `fitness-trainer` with its install-dir GLB, `yolo-hello`
  branding).
- **VENDORED** — `overlay.json` + `icon.svg` only; the code and the base
  `manifest.json` come from the `vendor/js_widget_runtime` submodule
  (`example/widgets/<id>/`, single source of truth). The merged manifest
  (base + overlay) is what validation, zips and `catalog.json` see.
- **EXTERNAL** — `overlay.json` with a REQUIRED `source` block; the code
  and the base `manifest.json` come from the author's own PUBLIC GitHub
  repo, pinned at `source.commit` (a full-sha pin). A publish PR adds
  exactly ONE file — the overlay; CI materializes the pinned tarball
  (`codeload.github.com/<repo>/tar.gz/<commit>`) into
  `vendor/external/<id>/` with `fa_widgets fetch`. Per-widget git
  submodules are RETIRED (flutter_agent_harness#232): no gitlink, no
  `.gitmodules` write.

### `widgets/<id>/overlay.json` (vendored and external)

| field | required | notes |
|-------|----------|-------|
| `icon` | yes (file must exist locally, or in the user repo for EXTERNAL) | path inside the widget folder |
| `tags` | – | free-form, lowercased by CI |
| `author` | – | defaults from the base manifest |
| `minRuntime` | yes | runtime floor, strict semver |
| `description` | – | overrides the base description |
| `source` | **EXTERNAL: yes** — forbidden for VENDORED | `{"repo": "owner/name", "commit": "<40-hex sha>"}` |

Any other key — especially `version` or `id` — is a validation ERROR:
those are single-sourced from the submodule manifest.

### EXTERNAL rules (pins-only catalog)

- A publish PR adds exactly one file — `widgets/<id>/overlay.json`.
  Parallel publishes from different devices are single-file PRs and
  cannot conflict; republishing an unchanged widget is a no-op.
- `source.repo` must be a GitHub `owner/name` slug
  (`[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+`); the repo MUST be public — catalog
  CI fetches tarballs anonymously (codeload).
- `source.commit` must be a full 40-hex sha (short shas cannot address a
  tarball). sha-addressed pins are immutable: a force-push never moves
  them; a pin to a missing sha fails fetch/validate with a named error.
- `dart run bin/fa_widgets.dart fetch` materializes every pin into
  `vendor/external/<id>/` (16 MiB tarball cap; a `.jsr-pin.json` marker
  records what was fetched — a stale or hand-placed directory is a
  validation error, re-run fetch).
- `.gitmodules` is FROZEN maintainer-owned data: its only legal entry is
  `vendor/js_widget_runtime`. Any other section (and any per-widget
  gitlink) is a validation ERROR — migrate to an overlay source pin.
The repo holds a normal widget at its root: `manifest.json` (same
  rules as a vendored CORE base manifest — `id` must equal the catalog
  folder name) plus `widget.js` or the manifest-declared live-tile entry
  (`widget.entry`). Version/id/permissions come from THAT manifest; the
  overlay carries catalog meta only.

Example:

```json
{
  "icon": "icon.svg",
  "tags": ["pomodoro"],
  "author": "Octocat",
  "minRuntime": "0.4.89",
  "source": {"repo": "octocat/fa-widget-focus", "commit": "637c99a7909c70910ddcd0600d81d9a4f741c1ba"}
}
```

The generated catalog entry carries the `source` block through (so the
Fa app can link the origin repo), and preview URLs point at
`raw.githubusercontent.com/<repo>/<commit>/…`.

## `widgets/<id>/manifest.json`

Runtime fields (consumed by the Fa app) + catalog metadata. Unknown keys are
warnings — schema evolves additively.

| Field | Type | Req | Notes |
| --- | --- | --- | --- |
| `id` | string | ✔ | `[a-z0-9][a-z0-9-]{1,31}`, MUST equal folder name |
| `name` | string | ✔ | human title |
| `description` | string | – | shown in gallery (missing → warning) |
| `version` | string | ✔ | strict semver `X.Y.Z` |
| `icon` | string | – | relative path, existing file (`.svg` recommended) |
| `author` | string | – | display credit |
| `tags` | list<string> | – | free-form, lowercased by CI |
| `platforms` | list<string> | – | OS targets: `ios`, `macos`, `android`, `windows`, `linux`, `web`; omit for runs-everywhere widgets. Unknown values → warning; mirrored into the catalog entry |
| `minRuntime` | string | ✔ | minimum `js_widget_runtime` version, e.g. `0.4.79` |
| `license` | string | – | defaults to repo MIT |
| `network` | bool | ✔ | `jsr.fetchJson` gate |
| `allowedCommands` | list<string> | ✔ | `jsr.exec` allowlist (runtime prompts regardless) |
| `permissions.*` | key/value | – | service gates: `llm`, `homekit`, `health`, `contacts`, `calendar`, `microphone`, `notifications`, `media`, `keys` |
| `widget` | object | – | live tile: `{entry, size: 'WxH', refreshSeconds, interactive}` — `interactive: true` routes tile taps to `jsr.onEvent` on the board instead of opening the app |

## Generated `catalog.json` entry

```json
{
  "id": "...", "name": "...", "version": "1.0.0",
  "description": "...", "author": "...", "tags": [],
  "platforms": ["ios", "macos"], // only when the manifest declares it
  "permissions": {"network": false, "allowedCommands": []},
  "minRuntime": "0.4.79", "icon": "icon.svg",
  "zip": {"file": "<id>-<version>.zip", "sha256": "<hex>", "sizeBytes": 1234}
}
```

Top level: `schemaVersion: 1`, `generatedAt` (UTC ISO-8601),
`sourceRepo`. Widgets sorted by `id`. Additive evolution only within
schemaVersion 1.

## Zip layout

Single root folder `<id>/` containing every file of the widget directory;
entries sorted by path; deflate. Consumers join asset names against
`https://github.com/IstiN/fa_widgets/releases/latest/download/`.
es sorted by path; deflate. Consumers join asset names against
`https://github.com/IstiN/fa_widgets/releases/latest/download/`.
