# Schema reference

## Two widget kinds

A `widgets/<id>/` folder is one of:

- **LOCAL** — `manifest.json` + `widget.js` (+ assets) all live here.
  Used for widgets calling Fa-specific APIs (`jsr.fa.*`) and conscious
  forks (e.g. `fitness-trainer` with its install-dir GLB, `yolo-hello`
  branding).
- **VENDORED** — `overlay.json` + `icon.svg` only; the code and the base
  `manifest.json` come from the `vendor/js_widget_runtime` submodule
  (`example/widgets/<id>/`, single source of truth). The merged manifest
  (base + overlay) is what validation, zips and `catalog.json` see.

### `widgets/<id>/overlay.json` (vendored only)

| field | required | notes |
|-------|----------|-------|
| `icon` | yes (file must exist locally) | path inside the widget folder |
| `tags` | – | free-form, lowercased by CI |
| `author` | – | defaults from the base manifest |
| `minRuntime` | yes | runtime floor, strict semver |
| `description` | – | overrides the base description |

Any other key — especially `version` or `id` — is a validation ERROR:
those are single-sourced from the submodule manifest.

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
