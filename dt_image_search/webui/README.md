# AuSearch Web UI

Vue UI hosted by the local index server and opened by the pywebview shell.
The API and process architecture are defined in
[`2026-10-04-web-ui-refactor-design.md`](../../docs/superpowers/specs/2026-10-04-web-ui-refactor-design.md).

Run these commands from the repository root:

```bash
pnpm -C dt_image_search/webui install --frozen-lockfile
pnpm -C dt_image_search/webui test
pnpm -C dt_image_search/webui build
bash scripts/run_app.sh
```

`build` checks TypeScript (including Vue templates) before producing `dist/`.
For frontend development, start an index server, then run Vite with its port
and token:

```bash
uv run --frozen python -m dt_image_search.index_server --auth-token local-dev
# Use the port from DTS_READY:
DTS_DEV_PORT=8000 VITE_DTS_TOKEN=local-dev pnpm -C dt_image_search/webui dev
```

`stores/status.ts` owns model readiness and refreshes the folder store from
the same status snapshot. Search and settings consume that shared state.
`stores/events.ts` restores it after every WebSocket connection, discards
responses from closed connections and tells mounted browse views to refresh.
Page-specific selection and loading state remain in their views.

Define visual values in `src/styles/tokens.css`; components reference the
`--dts-*` variables. The token tests build into a temporary directory, check
the resulting theme CSS and reject literal colors/dimensions in components.
