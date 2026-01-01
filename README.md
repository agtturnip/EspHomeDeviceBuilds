# ha_1pt_calibrated_env_boards

ESPHome packages-based composition for multiple ESP32 boards and environmental sensors.

Structure:
- core/   Shared device logic (wifi/api/ota/logger/time/diagnostics). No pins or sensors.
- boards/ Manufacturer-scoped board profiles (board type, pins, buses).
- features/ Manufacturer-scoped sensor/expander packages with explicit ids and names.
- builds/ Per-device folders with a build YAML and local secrets.

Workflow:
1. Create or update a board profile in boards/.
2. Create or update features in features/.
3. Create a build folder in builds/ with build.yaml and secrets.
4. Copy secrets: builds/<device>/secrets.example.yaml -> builds/<device>/secrets.yaml
5. Compile: esphome compile builds/<device>/build.yaml
6. Upload: esphome upload builds/<device>/build.yaml
7. Export single YAML (ESPHome Builder): scripts/export_build.sh builds/<device>

Notes:
- Keep entity names stable; avoid changing `name` or `id` unless required.
- Keep configuration declarative; do not use runtime detection.
