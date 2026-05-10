# Agent Notes

## What This App Is

This repository is a customized LDtk/Electron/Haxe editor for Ripped Sails content. It is a desktop app built with:

- Haxe renderer code in `src/electron.renderer`, compiled to `app/assets/js/renderer.js`.
- Haxe Electron main code in `src/electron.main`, compiled to `app/assets/main.js`.
- HTML templates in `app/assets/tpl/pages`.
- App assets and Electron package files under `app`.

It includes LDtk project editing plus custom tools such as the Ship Editor and World Map Editor. Treat it as a real desktop app: UI behavior should be verified visually when practical, not only by reading code.

## Verification Is Expected

Agents may and should run builds, checks, the Electron app, CDP/browser automation, and screenshot-based verification when it helps validate a change. Do not leave verification to the user when it is feasible in the Docker container.

Important: do not run Haxe, LDtk/Electron builds, `./run.sh`, Electron, Node app tooling, or project test commands directly on the host machine. The host shell may be used for reading files, editing files, `git`, `rg`, and other lightweight repository inspection only. All app build/runtime verification must happen through the Docker devcontainer.

If the devcontainer is not already running, start it from the repo root:

```bash
docker compose -f .devcontainer/compose.yml up -d gui
```

Docker-only build commands:

```bash
docker exec -w /workspace <container-id-or-name> bash -lc 'HAXELIB_PATH=/usr/share/haxe/lib haxe main.debug.hxml'
docker exec -w /workspace <container-id-or-name> bash -lc 'HAXELIB_PATH=/usr/share/haxe/lib haxe renderer.debug.hxml'
```

Do not run `./run.sh` on the host. If an end-to-end run is needed, run the equivalent build and Electron commands inside Docker.

If sandboxing blocks Docker, local ports, or GUI execution, request escalation with a narrow justification. Do not fall back to host-local Haxe/build execution.

## Runtime And Screenshot Checks

For UI changes, especially renderer pages, verify the app visually when practical:

1. Build the changed target, usually `renderer.debug.hxml`.
2. Start Electron with a remote debugging port, preferably headless in Docker:

```bash
docker exec -w /workspace/app <container-id-or-name> bash -lc 'xvfb-run -a ./node_modules/.bin/electron --no-sandbox --disable-gpu --disable-dev-shm-usage --remote-debugging-address=127.0.0.1 --remote-debugging-port=9235 .'
```

3. Use CDP, Playwright, or another browser automation tool to click through the affected screen.
4. Capture screenshots of important states and copy them to `/private/tmp` when useful for the final answer.
5. Any screenshot captured from Docker visual checks must be shown visibly in the final chat summary using Markdown image syntax with an absolute `/private/tmp/...` path, not only mentioned as a file path.
6. Check canvas-heavy screens by sampling pixels, not only by checking that a canvas element exists.
7. Stop Electron/Xvfb processes started for the test before finishing.

When testing with temporary app settings or files, restore them afterward. Debug settings live under `app/settings/settings.cfg`.

## Project-Specific Pointers

- Page templates are loaded by `loadPageTemplate("<name>")`; for example `worldMapEditor` maps to `app/assets/tpl/pages/worldMapEditor.html`.
- Renderer pages commonly live in `src/electron.renderer/page`.
- Shared app settings use `App.ME.settings`.
- File dialogs use `dn.js.ElectronDialogs`.
- Node/file helpers are usually exposed through `NT`.
- Prefer existing UI patterns from nearby pages, especially `ShipEditor`, before inventing a new flow.
- Preserve user changes in the working tree. Check `git status --short` before and after larger edits.
- Run `git diff --check` before finishing code or template changes.
