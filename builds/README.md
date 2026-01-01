# builds/

Per-device folders. Each device folder should contain:
- `build.yaml` with substitutions and package includes.
- `secrets.yaml` (local, not committed) copied from `secrets.example.yaml`.
 - `export/` for generated single-file YAML output (ignored by git).

Template:
- Copy `builds/_template/` to a new folder and edit `build.yaml`.

Export:
- Run `scripts/export_build.sh builds/<device>` to generate `export/<device>.yaml`.
