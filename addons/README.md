# Vendored addons

Third-party code lives only in `addons/` and `server/node_modules` (not committed). Record every addition here with its version and licence.

| Addon | Version | Licence | Used for |
|---|---|---|---|
| GUT (`addons/gut/`) | 9.7.1 | MIT | Unit and integration tests |
| Nakama Godot client (`addons/com.heroiclabs.nakama/`, heroiclabs/nakama-godot) | v3.4.0 (unmodified; Godot 4 branch) | Apache-2.0 (`addons/com.heroiclabs.nakama/LICENSE`) | Online client, used only from `src/game/net/**`. Its autoload is NOT enabled: `NakamaBackend` instantiates `Nakama.gd` as a plain child node instead. |
