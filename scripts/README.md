# scripts/

Local helper scripts for this repository. These scripts are meant to be run on your machine
and may output files that contain secrets. Do not commit generated outputs.

export_build.sh
- Purpose: export a fully resolved, single-file YAML per build folder, or compile/upload.
- Inputs: `builds/<device>/build.yaml` plus `builds/<device>/secrets.yaml`.
- Output (export): `builds/<device>/export/<device>.yaml` (contains secrets).
- Output (bin): firmware `.bin` files copied into `builds/<device>/export/`.

Usage:
- Interactive mode (choose build + action):
  `scripts/export_build.sh`
- Export YAML only (non-interactive):
  `scripts/export_build.sh builds/<device>`
- Export YAML for all builds:
  `scripts/export_build.sh all`

Notes:
- The export uses `esphome config --show-secrets`, so the output includes secrets.
- The `export/` folder is gitignored to prevent accidental commits.
- If no USB serial device is detected, the script will offer an OTA upload instead.
