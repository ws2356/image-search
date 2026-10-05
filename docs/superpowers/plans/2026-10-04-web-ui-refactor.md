# AuSearch Web UI 重构实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 AuSearch 主 UI 迁移为 Vue3 Web UI(HTTP+WS),核心索引/查询逻辑收敛到独立 index server 进程,壳用 pywebview,移除主 UI 路径上的 Qt 依赖。

**Architecture:** 壳进程(pywebview+pystray)拉起 index server 子进程(FastAPI,stdio 握手 port+token),server 静态托管 Vue3 构建产物并复用现有核心模块(`dts_index`/`dts_db`/worker/`bm_fs_monitor`);`dts_event_bus` 事件经 EventBridge 推送 WS。

**Tech Stack:** Python 3.10 + FastAPI/uvicorn + pywebview + pystray(新增代码 async-first,渐进迁移);Vue3 + Vite + Pinia + **Element Plus**(design token 主题)+ Vitest(pnpm);Python 命令一律 `uv run`。

**Spec:** `docs/superpowers/specs/2026-10-04-web-ui-refactor-design.md`

## Global Constraints

- Python 3.10;所有 Python 进程/命令一律经 `uv run` 执行(仓库根有 `uv.lock`),禁止直接裸调 `python`/`pip`。测试:`uv run bash scripts/run_tests.sh`(全量)或 `uv run pytest <file> -v`(单文件)。
- **数据格式完全不变**:app data 路径、`app_data.sqlite` schema、`*.faiss` 文件名/格式、`model_cache/` 结构、`app_config` 键值。新文件只允许出现在新增子目录 `app_data/thumb_cache/`(旧版本会忽略,属增量不属变更)。
- index server 仅监听 `127.0.0.1`;所有 HTTP 端点与 WS 要求 token(header `X-Auth-Token` 或 query `auth`)。
- 本期**不改动、不接线** mobile 功能(`mobile/` 目录与 mobile 相关测试保持原样;Qt 移除仅限主 UI 路径)。
- 前端包管理一律 `pnpm`(禁止 npm/yarn);webui 依赖固定版本。
- **UI 框架**:webui 一律使用 **Element Plus** 组件(按官方最佳实践:`unplugin-auto-import` + `unplugin-vue-components` 的 `ElementPlusResolver` 自动导入);样式值(颜色/间距/字号/圆角)只允许引用 design token(`webui/src/styles/tokens.css` 的 `--dts-*` 变量,并映射到 Element Plus 的 `--el-*` 主题变量),组件内禁止写裸色值/尺寸。
- **asyncio 迁移原则(渐进式)**:以本次重构为起点,**新增代码 async-first**——index server 路由 handler 一律 `async def`,调用既有同步核心模块经 `asyncio.to_thread(...)` 包装,事件循环内禁止直接执行阻塞 I/O;既有同步代码**不要求**重写为 asyncio。
- 每个任务完成:测试通过 → `git commit -m "... [LLM: glm-5.3-flash]"`。
- 新 Python 测试文件需要 stub 重依赖时,沿用 `tests/unit/test_dts_index.py:22-62` 的 `sys.modules` stub 模式;`dt_image_search/conftest.py` 已 stub `aiortc`。

## Review Focus

1. **缩略图/原图路径越权**:请求未注册或伪造的 file id → 404,绝不按客户端输入拼文件路径(Task 6 步骤 4)。
2. **无 token 访问**:浏览器直开任意 API/WS → 401/连接被拒,静态页面本身也要求 token 才可用(Task 4 步骤 3、Task 7 步骤 3)。
3. **server 崩溃后 WS 恢复**:断线重连采用指数退避,重连成功后 UI 重新拉取 status,不残留僵尸进度条(Task 12 步骤 3)。
4. **重复/嵌套添加 folder**:`POST /folders` 对已存在目录或已有 folder 的子目录幂等返回既有 folder,不建重复行、不重复入队索引(Task 5 步骤 2)。
5. **模型未就绪时搜索**:返回 503 + 当前 model state,UI 显示"模型加载中"提示,而非空结果假象(Task 5 步骤 2)。

---

### Task 0: 前置准备——asyncio 集成约定落地

**Files:**
- Create: `docs/superpowers/specs/2026-10-04-asyncio-migration-notes.md`
- Test: 无(文档任务;后续任务的测试即其验证)

**Interfaces:**
- Produces: 仓库级 asyncio 约定文档,后续任务(Task 4-8)引用执行。内容钉死为:
  1. **范围**:index server 与 webui 配套的 Python 侧新代码 async-first;既有同步核心(`dts_db`/`dts_index`/worker/`bm_fs_monitor`)不重写。
  2. **边界规则**:async → sync 只允许一种写法:`await asyncio.to_thread(fn, ...)`(或路由内直接 `await to_thread` 包装的 service 调用);sync → async 只允许一种写法:EventBridge 的 `broadcast_threadsafe`(`asyncio.run_coroutine_threadsafe` 到 uvicorn 主 loop)。禁止再引入其他桥接方式(one way to do things)。
  3. **禁止事项**:在 `async def` 内直接调用阻塞 I/O(文件/SQLite/网络);在事件循环线程内启动自己的 `asyncio.run`;在线程内创建事件循环后与主 loop 通信(必须走 broadcast 模式)。
  4. **演进方向**:后续 Touch 到的同步模块逐步迁 asyncio;mobile 迁移(下一期)时新代码同样 async-first。

- [ ] **Step 1:** 写上述四节内容到 `docs/superpowers/specs/2026-10-04-asyncio-migration-notes.md`,不超过一页。
- [ ] **Step 2: Commit** `docs: asyncio migration conventions for web-ui refactor`

### Task 1: Qt-free 状态消息通道(替代 status_bar_messenger)

**Files:**
- Create: `dt_image_search/tools/status_messenger.py`
- Modify: `dt_image_search/index/dts_index.py`、`dt_image_search/index/index_worker.py`、`dt_image_search/index/incremental_index_worker.py`、`dt_image_search/index/dts_model_downloader.py`、`dt_image_search/search/SearchController.py`(全部把 `status_bar_messenger.show_status_message.emit(msg)` 换成 `status_messenger.show(msg)`)
- Modify: `dt_image_search/__main__.py`(~line 499 `_on_show_status_message` 改为订阅新通道)
- Test: `tests/unit/test_status_messenger.py`

**Interfaces:**
- Produces: `dt_image_search.tools.status_messenger.show(message: str) -> None`;`subscribe(callback: Callable[[str], None]) -> Disposable`(`.dispose()`)。后续 EventBridge(Task 7)以事件名 `"status_message"` 订阅 default_bus 或直接调 `subscribe`。
- 兼容:Qt UI 仍工作——`__main__.py` 中 `status_messenger.subscribe(lambda m: status_bar_messenger.show_status_message.emit(m))`(桥接保留至 Qt UI 删除)。

- [ ] **Step 1: 写失败测试** — `show` 依次调用所有已订阅 callback;`dispose` 后不再收到;callback 异常不影响其他订阅者(沿用 `dts_event_bus` 的打印-不抛约定)。
- [ ] **Step 2:** `uv run pytest tests/unit/test_status_messenger.py -v` → FAIL(模块不存在)。
- [ ] **Step 3:** 实现 `tools/status_messenger.py`(纯 Python,无 Qt import,`threading.Lock` 保护订阅列表)。
- [ ] **Step 4:** 上述 5 个文件把 `from dt_image_search.base.status_bar_messenger import status_bar_messenger` 换成新通道(emit→show);`__main__.py` 加桥接订阅。
- [ ] **Step 5:** `uv run pytest tests/unit/ -v` 全绿(尤其 `test_index_worker.py`、`test_model_state.py`、`test_search_controller.py`)。
- [ ] **Step 6: Commit** `refactor: qt-free status messenger for core modules`

### Task 2: Qt-free 搜索编排 search_service

**Files:**
- Create: `dt_image_search/search/search_service.py`
- Modify: `dt_image_search/search/SearchController.py`(`on_search_query`/`_search_in_folder` 委托给 service;dispatcher/Qt model 更新留在 controller)
- Test: `tests/unit/test_search_service.py`

**Interfaces:**
- Consumes: `dts_db.get_all_folders(conn)`、`dts_index.query_index(ctx, folder_id, index_path, query_text) -> list[(File, score)]`、`dts_index.TOP_K`(=100)、`dts_index.get_model_state()`。
- Produces: `search_folders(ctx: BMContext, query: str) -> list[tuple[File, float]]` — 遍历全部 folder 合并、按 score 降序、截断 TOP_K;模型非 ready 时 `raise ModelNotReadyError(state)`(自定义异常,含 state 字符串)。
- `SearchController` 保留:debounce、dispatcher.post 到 `ImageListModel`、status 消息。

- [ ] **Step 1: 写失败测试** — 两个 folder 各返回结果 → 合并降序;超过 TOP_K 截断为 100;无 folder → `[]`;`get_model_state()=="loading"` → `ModelNotReadyError`。stub 模式同 `test_dts_index.py`。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现 `search_folders`(把 `SearchController._search_in_folder` 的循环逻辑原样搬移,controller 改为调用它)。
- [ ] **Step 4:** pytest 单文件 + `test_search_controller.py` → PASS。
- [ ] **Step 5: Commit** `refactor: extract qt-free search_service`

### Task 3: Qt-free 文件夹服务 folder_service

**Files:**
- Create: `dt_image_search/browse/folder_service.py`
- Modify: `dt_image_search/browse/BrowseController.py:74-200`(`on_folder_added`/`on_delete_folder` 委托 service,Qt model/broadcast 部分留在 controller)
- Test: `tests/unit/test_folder_service.py`

**Interfaces:**
- Consumes: `dts_db.match_parent_folder(conn, path)`、`insert_folder(conn, folder_path) -> Folder|None`(已存在返回 None)、`get_subfolders`、`dts_index.delete_folder(ctx, folder_path)`、`bm_fs_monitor.add_folder(path)/remove_folder(path)`、`index_worker.add_index_worker(ctx, folder)`、`dts_util.normalized_folder_path`。
- Produces:
  - `add_folder(ctx: BMContext, folder_path: str) -> Folder | None`:normalize → `match_parent_folder` 命中父级即视为已存在(返回该父级 Folder)→ `insert_folder` 返回 None 也返回既有 folder(`get_folder_by_path`)→ 否则 `fs_monitor.add_folder` + `add_index_worker`(仅当 status != 2),返回新 Folder。
  - `remove_folder(ctx: BMContext, folder_path: str) -> None`:`fs_monitor.remove_folder` → `default_bus.publish("folder_deleted_from_ui", folder_path=...)` → `dts_index.delete_folder(ctx, folder_path)`。
  - `reindex_folder(ctx: BMContext, folder: Folder) -> None`:`dts_db.update_folder_status(conn, folder.id, 0)` + `add_index_worker(ctx, folder)`。

- [ ] **Step 1: 写失败测试**(mock `dts_index`/`index_worker`/`bm_fs_monitor`,真 SQLite 内存库测 `add_folder` 幂等/父子命中)。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现 service;`BrowseController.on_folder_added`/`on_delete_folder` 改为调用 service 后再做自己的 Qt model 更新(行为不变)。
- [ ] **Step 4:** pytest 单文件 + `test_browse_controller_mobile_folder.py` → PASS。
- [ ] **Step 5: Commit** `refactor: extract qt-free folder_service`

### Task 4: index server 骨架(app 工厂 + token 认证 + 静态托管 + READY 握手)

**Files:**
- Create: `dt_image_search/index_server/__init__.py`
- Create: `dt_image_search/index_server/app.py`(`create_app(ctx, token, static_dir) -> FastAPI`)
- Create: `dt_image_search/index_server/auth.py`
- Create: `dt_image_search/index_server/main.py`(入口)
- Test: `tests/unit/test_index_server_auth.py`、`tests/unit/test_index_server_app.py`

**Interfaces:**
- Produces:
  - `create_app(ctx: BMContext, token: str, static_dir: str | None = None) -> FastAPI`;`GET /health` 200(health 不需要 token,供壳探活;其余路由挂 `require_token` 依赖:`X-Auth-Token` header 或 `auth` query,失败 401)。**所有路由 `async def`**(asyncio 约定,见 Task 0 文档)。
  - `main.py`:`uv run python -m dt_image_search.index_server --auth-token <t> [--static-dir <dir>]`:解析参数 → 建 `BMContext`(沿用 `__main__.py` 顶部的 env 设定,提取为函数 `setup_process_env()` 复用)→ uvicorn 监听 `127.0.0.1`、`port=0` → 启动完成后向 stdout 打印一行 `DTS_READY <port>`(uvicorn `startup` 事件里从 `server.servers[0].sockets[0].getsockname()[1]` 取实际端口)。
  - `static_dir` 提供时挂 `StaticFiles(html=True)` 于 `/` 并带 SPA fallback(未知路径→`index.html`)。

- [ ] **Step 1: 写失败测试** — 无 token 访问受保护路由 → 401;带 `X-Auth-Token`/`auth` query → 200;`/health` 无 token → 200。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现 `auth.py`(FastAPI dependency)+ `app.py` 工厂。
- [ ] **Step 4:** pytest → PASS。
- [ ] **Step 5: 写失败测试(READY 行)** — `subprocess` 起 `main.py`(stub ctx 或 `--skip-model-init` 测试开关),stdout 收到 `DTS_READY <port>` 后 `curl /health` 200、进程退出时清理。
- [ ] **Step 6:** pytest → PASS。
- [ ] **Step 7: Commit** `feat: index server skeleton with token auth and ready handshake`

### Task 5: folder / search / browse / reindex 路由 + get_file_by_id

**Files:**
- Create: `dt_image_search/index_server/routes.py`、`dt_image_search/index_server/serializers.py`
- Modify: `dt_image_search/model/dts_db.py`(新增 `get_file_by_id(conn, file_id: int) -> File | None`,实现参考 `get_file_by_path` line 193)
- Modify: `dt_image_search/model/db_schema.sql` — **不改**;仅确认新查询用现有索引
- Test: `tests/unit/test_index_server_routes.py`、`tests/unit/test_get_file_by_id.py`

**Interfaces:**
- Consumes: Task 2/3 的 `search_folders`/`add_folder`/`remove_folder`/`reindex_folder`;`dts_db.get_all_folders/get_folder_by_id/delete_folders`。路由一律 `async def`,对同步核心的调用经 `asyncio.to_thread(...)`(Task 0 约定)。
- Produces(序列化契约,Task 9-12 前端依赖):
  - `GET /folders` → `{"folders": [{"id","path","status","added_at"}]}`(id 为字符串)
  - `POST /folders {"path": str}` → 201 + folder 对象;已在库/命中父级 → 200 + 既有 folder(幂等)
  - `DELETE /folders/{id}` → 204;不存在 → 404
  - `POST /folders/{id}/reindex` → 202;folder 不存在 → 404;status==2 → 200(无需重建,返回现状)
  - `GET /search?q=&limit=` → `{"results": [{"id","path","folder_id","score"}]}`;`ModelNotReadyError` → 503 `{"detail": {"model_state": "loading"}}`
  - `GET /browse?folder_id=&path=` → `{"folder": {...}, "subfolders": [...], "files": [{"id","path","status"}]}`(path 缺省为 folder 根;`get_subfolders` + `get_direct_child_files`,只返回 `is_image_file` 命中的文件)

- [ ] **Step 1: 写失败测试**(`dts_db.get_file_by_id`:命中/未命中;路由:幂等添加、嵌套父级命中、404 分支、503 分支;内存 SQLite + stub 重依赖)。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现 serializers(`folder_to_dict`/`file_to_dict`)与 routes,委托 service 层,不在路由里写业务逻辑。
- [ ] **Step 4:** pytest → PASS。
- [ ] **Step 5: Commit** `feat: index server folder/search/browse routes`

### Task 6: 缩略图与原图路由(media)

**Files:**
- Create: `dt_image_search/index_server/media.py`、路由加在 `routes.py`
- Modify: `dt_image_search/model/dts_db.py`(Task 5 已加 `get_file_by_id`,此处只消费)
- Test: `tests/unit/test_index_server_media.py`

**Interfaces:**
- Produces: `class ThumbnailCache: __init__(cache_dir: str, max_memory_items: int = 512)`;`get_or_build(file: File, size: int = 300) -> str`(缩略图磁盘路径;磁盘缓存键为 `<sha1(file.path)>_<size>.jpg`,位于 `app_data/thumb_cache/`,内存 LRU 存路径;源文件已消失 → `FileGoneError`)。路由:`GET /thumb/{file_id}` 与 `GET /file/{file_id}`(原图 `FileResponse`),按 `file.path` 供给;id 不存在或文件缺失 → 404。
- 缩略图生成:PIL `draft()` 降采样(pillow-heif 支持 heic,沿用 `image_processor.py` 的尺寸上限策略);路由 `async def`,生成/读盘经 `asyncio.to_thread`。

- [ ] **Step 1: 写失败测试** — 生成缩略图并二次命中磁盘缓存(不重新解码);不存在的 id → 404;`cache_dir` 外路径不会被拼接(用 `file.path` 只作数据源断言);原图路由返回 `image/jpeg|png` Content-Type。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现 `media.py` + 路由(`File.path` 仅供服务端读取文件,客户端永不传路径)。
- [ ] **Step 4:** pytest → PASS。
- [ ] **Step 5: Commit** `feat: index server thumbnail/original-image routes`

### Task 7: EventBridge + WS /events

**Files:**
- Create: `dt_image_search/index_server/ws.py`(ConnectionManager/EventBroker)、`dt_image_search/index_server/event_bridge.py`
- Modify: `dt_image_search/index_server/app.py`(挂 `/events` WS 路由)
- Test: `tests/unit/test_event_bridge.py`、`tests/unit/test_ws_broker.py`

**Interfaces:**
- Produces:
  - `EVENT_NAMES = ("status_message", "fs_changed", "folder_deleted_from_ui", "model_load_failed")`(常量,冻结)。
  - `class EventBroker`: `async connect(token, websocket)`(token 校验失败→close 1008)、`broadcast_threadsafe(payload: dict)`(任意线程可调,`asyncio.run_coroutine_threadsafe` 到 server loop)。
  - `attach_event_bridge(broker) -> Disposable`:对 `EVENT_NAMES` 逐一 `default_bus.subscribe(name, lambda **kw: broker.broadcast_threadsafe({"event": name, "data": kw}))`;`Disposable.dispose()` 退订。消息信封 `{"event": str, "data": dict}`,data 里的 watchdog event 对象替换为其字符串摘要(type/src_path)以保证可 JSON 序列化。

- [ ] **Step 1: 写失败测试** — broker:connect 校验 token;broadcast 到多个已连客户端(fakews);bridge:publish `"status_message"` → 客户端收到 `{"event":"status_message","data":{"message":...}}`;非白名单事件不转发;dispose 后不再转发。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现 broker 与 bridge;`app.py` 挂 `/events`。
- [ ] **Step 4:** pytest → PASS。
- [ ] **Step 5: Commit** `feat: index server event bridge over websocket`

### Task 8: index server 主进程装配(main.py 完整版)

**Files:**
- Modify: `dt_image_search/index_server/main.py`(在 Task 4 骨架上补启动序列)
- Test: `tests/unit/test_index_server_main.py`

**Interfaces:**
- Consumes:`__main__.py` 的启动序列改为可复用:`model_downloader_init(ctx)` → `index_init(ctx)` → `init_incremental_index_workers(ctx)` → `init_index_workers(ctx)` → `start_watch(ctx)`;退出时 `stop_watch()`/`deinit_*`。
- Produces:`main.py --auth-token <t>` 完整启动:setup_process_env → ctx → create_app(挂 Task 5/6 路由 + Task 7 bridge)→ uvicorn → `DTS_READY <port>` → 阻塞服务;SIGTERM/SIGINT 走与 `__main__.py cleanup()` 相同的清理顺序。

- [ ] **Step 1: 写失败测试** — monkeypatch 上述 init 函数,断言装配顺序与退出清理顺序;`--skip-model-init`(测试开关)时不调用模型 init。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现(从 `__main__.py:875-879` + `cleanup():808-816` 提取共享函数,`__main__.py` 与 `main.py` 共用,DRY)。
- [ ] **Step 4:** pytest → PASS;`uv run bash scripts/run_tests.sh` 全绿。
- [ ] **Step 5: Commit** `feat: index server process assembly`

### Task 9: webui 脚手架(pnpm + Vite + Vue3 + Pinia + Vitest)

**Files:**
- Create: `dt_image_search/webui/`(`package.json`、`vite.config.ts`、`tsconfig.json`、`index.html`、`src/main.ts`、`src/App.vue`、`src/router/index.ts`)
- Create: `dt_image_search/webui/src/styles/tokens.css`(design token:语义变量 `--dts-color-*`/`--dts-space-*`/`--dts-font-*`/`--dts-radius-*`,并在 `:root` 映射到 Element Plus 主题变量 `--el-color-primary`、`--el-bg-color` 等)
- Create: `dt_image_search/webui/.gitignore`(`node_modules/`、`dist/`)
- Modify: `dt_image_search/index_server/app.py`:`--static-dir` 缺省指向 `webui/dist`(存在时)
- Test: `dt_image_search/webui/tests/smoke.spec.ts`、`tests/tokens.spec.ts`

**Interfaces:**
- Produces: `pnpm -C webui dev`(开发,vite proxy 将业务前缀 `/folders|/search|/browse|/status|/events|/thumb|/file` 转发到 `http://127.0.0.1:<DTS_DEV_PORT>`,token 从 `VITE_DTS_TOKEN` 读)、`pnpm -C webui build`(产出 `webui/dist`)、`pnpm -C webui test`(vitest)。路由:`/`(浏览)、`/search`、`/settings`、`/viewer/:fileId`(createWebHistory)。
- **Element Plus 集成(官方最佳实践)**:依赖 `element-plus` + `unplugin-auto-import` + `unplugin-vue-components`(resolver: `ElementPlusResolver`);`main.ts` 引入 `tokens.css`;组件经 auto-import 使用,不手写 `import { ElButton }`。
- **Design token 约则**:`tokens.css` 定义语义层 `--dts-*`(色板、间距、字号、圆角、阴影),`--el-*` 主题变量全部由 `--dts-*` 映射(如 `--el-color-primary: var(--dts-color-primary)`);后续所有组件样式只引用 `--dts-*`,不允许出现裸 hex/px 尺寸。
- 固定版本:vue ^3.5、element-plus ^2.13、vite ^7、pinia ^3、vue-router ^4.5、vitest ^3(以锁定日期最新 minor 为准,写死在 package.json)。

- [ ] **Step 1:** 手写最小脚手架(含上述 Element Plus 插件配置);`tokens.css` 初版定义 Primary/语义色与间距/字号/圆角三组 token。
- [ ] **Step 2:** `smoke.spec.ts` 断言 `App.vue` 渲染出根容器;`tokens.spec.ts` 断言构建产物 CSS 含 `--dts-*` 定义且 `--el-color-primary` 由其映射。
- [ ] **Step 3:** `pnpm -C webui test` → PASS;`pnpm -C webui build` 成功。
- [ ] **Step 4: Commit** `feat: webui scaffold (vue3 + vite + pinia + element plus, pnpm, design tokens)`

### Task 10: webui API client(带 token)

**Files:**
- Create: `dt_image_search/webui/src/api/client.ts`、`src/api/types.ts`、`src/auth/token.ts`
- Test: `dt_image_search/webui/tests/api-client.spec.ts`

**Interfaces:**
- Consumes: Task 5/6 的 HTTP 契约(路径、query、响应形状、错误码 401/404/503)。
- Produces:
  - `token.ts`:`getToken(): string | null`(从 URL `?auth=` 提取一次,存内存 + `sessionStorage`;后续请求从内存读)。
  - `client.ts`:`listFolders()`、`addFolder(path)`、`deleteFolder(id)`、`reindexFolder(id)`、`search(q, limit?)`、`browse(folderId, path?)`、`thumbUrl(id)`/`fileUrl(id)`(返回带 `?auth=` 的 URL 字符串,供 `<img>`)、`getStatus()`;错误映射:`ApiError{status, detail}`;503 时抛 `ModelNotReady`。

- [ ] **Step 1: 写失败测试**(fetch mock):token 注入 header 与 query;401/503/404 错误映射;`thumbUrl` 拼 `?auth=`。
- [ ] **Step 2:** `pnpm -C webui test` → FAIL。
- [ ] **Step 3:** 实现 `types.ts`(与 Task 5 契约逐字段一致的 TS interface)+ `client.ts` + `token.ts`。
- [ ] **Step 4:** 测试 PASS;build 通过。
- [ ] **Step 5: Commit** `feat: webui api client with token auth`

### Task 11: webui 搜索页 + 浏览页

**Files:**
- Create: `dt_image_search/webui/src/stores/search.ts`、`src/stores/folders.ts`、`src/views/SearchView.vue`、`src/views/BrowseView.vue`、`src/components/ImageGrid.vue`、`src/components/FolderTree.vue`、`src/components/AddFolderButton.vue`
- Test: `dt_image_search/webui/tests/search-store.spec.ts`、`tests/folders-store.spec.ts`

**Interfaces:**
- Consumes: Task 10 client;Task 7 事件名(`fs_changed` 触发 browse 重拉、`status_message` 显示横幅)。
- Produces:
  - `useSearchStore`: `query, results, searching, modelState`;action `runSearch(q)`(输入 300ms 防抖、`ModelNotReady` → `modelState='loading'` 提示而非空结果)。
  - `useFoldersStore`: `folders, load(), add(path)(幂等分支:200 既有/201 新建都收敛为同一 refresh), remove(id)`。
  - `ImageGrid`:缩略图 `thumbUrl` 懒加载(`loading="lazy"`),点击 → `router.push('/viewer/'+id)`;`FolderTree`:folder 状态徽标(0/1/2/3)与删除按钮。
  - **组件约定**:优先复用 Element Plus 组件(`el-input`/`el-button`/`el-empty`/`el-tooltip` 等),自定义组件只补 EP 没有的形态;样式只引用 `--dts-*` token(见 Task 9)。
- [ ] **Step 1: 写失败 store 测试**(防抖只发一次请求;幂等添加后 folders 恰好一条;503 分支)。
- [ ] **Step 2:** vitest → FAIL。
- [ ] **Step 3:** 实现两个 store + 三个组件 + 两个视图(纯展示与状态编排,无业务计算)。
- [ ] **Step 4:** vitest PASS;`pnpm -C webui build` 通过。
- [ ] **Step 5: Commit** `feat: webui search & browse pages`

### Task 12: webui 实时事件(WS store)+ 图片查看器 + 设置页

**Files:**
- Create: `dt_image_search/webui/src/stores/events.ts`、`src/views/ViewerView.vue`、`src/views/SettingsView.vue`、`src/components/StatusBanner.vue`
- Test: `dt_image_search/webui/tests/events-store.spec.ts`

**Interfaces:**
- Consumes: Task 7 WS 契约(`{"event","data"}`;`?auth=` query);Task 10 `fileUrl/getStatus`。
- Produces: `useEventsStore`:连接 `WS /events?auth=`;**指数退避重连**(1s/2s/4s/…/30s 封顶),重连成功后调 `getStatus()` 刷新;`status_message` → StatusBanner 最新一条;`fs_changed` → 触发 folders/browse 刷新;`model_load_failed` → 全局错误横幅。Viewer:`fileUrl(fileId)` 原图 + 左右键导航(基于当前列表)。Settings:展示 `GET /status`(模型 state、各 folder 状态汇总)。

- [ ] **Step 1: 写失败测试**(mock WebSocket):事件分发;断线 3 次后退避间隔递增;重连成功触发 status 刷新;`fs_changed` 后调用 browse 刷新回调。
- [ ] **Step 2:** vitest → FAIL。
- [ ] **Step 3:** 实现 store + 三个视图/组件。
- [ ] **Step 4:** vitest PASS;build 通过。
- [ ] **Step 5: Commit** `feat: webui live events, viewer, settings`

### Task 13: 壳进程(ShellApi + shell_main + 托盘 + 单实例 + macOS 菜单)

**Files:**
- Create: `dt_image_search/shell/__init__.py`、`dt_image_search/shell/pywebview_api.py`、`dt_image_search/shell/shell_main.py`、`dt_image_search/shell/macos_menu.py`、`dt_image_search/shell/server_process.py`
- Test: `tests/unit/test_shell_api.py`、`tests/unit/test_server_process.py`

**Interfaces:**
- Consumes: Task 4 的 `DTS_READY <port>` 握手契约;Task 10 的 `?auth=` URL 约定。
- Produces:
  - `server_process.py`:`class ServerProcess`: `start() -> None`(生成一次性 token,`sys.executable -m dt_image_search.index_server --auth-token <t>`,stdout 逐行读,遇 `DTS_READY <port>` 回调 `on_ready(port)`;EOF/进程退出回调 `on_exit()` 并自动重启一次,连续失败停止)、`stop()`、`port/token` 属性。
  - `pywebview_api.py`:`class ShellApi: pick_folder() -> str | None`(`webview.create_file_dialog(FOLDER_DIALOG)`,取消返回 None)、`reveal(file_path: str)`(macOS `open -R`、Windows `explorer /select,`、Linux `xdg-open` 目录;仅接受 server 侧已登记路径——由前端传 fileUrl 对应 path,壳不校验 DB,信任边界在 server)。
  - `shell_main.py`:单实例锁(复用 `__main__.py` 现有机制)→ 启 ServerProcess → `on_ready` 时 `webview.create_window(url=f"http://127.0.0.1:{port}/?auth={token}", js_api=ShellApi())` → `webview.start()`;托盘(pystray:显示/退出)与窗口共存;`macos_menu.py` 仅 darwin 加载(PyObjC 构造 About/Quit/显示窗口)。
- [ ] **Step 1: 写失败测试** — ShellApi:fake `webview` 模块下 pick_folder 返回选中/None;reveal 按平台映射正确命令(monkeypatch subprocess)。ServerProcess:fake Popen,READY 行解析、崩溃重启一次后不再无限重启。
- [ ] **Step 2:** pytest → FAIL。
- [ ] **Step 3:** 实现四个模块。
- [ ] **Step 4:** pytest PASS;`uv run bash scripts/run_tests.sh` 全绿;手动冒烟:`uv run python -m dt_image_search.shell --static-dir webui/dist` 能选目录→建索引→搜索→查看(记录进 PR 描述)。
- [ ] **Step 5: Commit** `feat: pywebview shell with tray and server process management`

### Task 14: 打包、入口切换、Qt 清理与数据兼容验收

**Files:**
- Modify: `scripts/build_pyinstaller.sh`、`DTImageSearch.spec`(双进程:壳为主可执行,index server 作为 bundle 内资源以子进程释放/启动;`webui/dist` 与模型静态资源打包)
- Modify: `requirements.txt`(主 UI 路径不再需要的 Qt 项:`pyside6` 保留注释 `# mobile 子系统下一期移除`)
- Modify: `dt_image_search/__main__.py`(Qt 入口保留但不再作为默认)
- Create: `scripts/run_app.sh`(默认入口 = shell)
- Create: `docs/mobile-folder/[dev]webui-refactor-data-compat-checklist.md`(见 Step 3)

**Interfaces:**
- Produces: 构建命令不变(`bash scripts/build_pyinstaller.sh`);新增验收文档。

- [ ] **Step 1:** 更新 spec 文件与构建脚本,产出可启动的 app(macOS 先行;MSIX 留 TODO 注释)。
- [ ] **Step 2:** 手动冒烟:打包产物完成 Task 13 冒烟清单。
- [ ] **Step 3:** **数据兼容验收**(对照 Spec 兼容性约束):用既有 app data 目录 ① 旧 Qt 版启动 → 记录 `app_data` 文件清单与 `app_config` 内容;② 新壳版启动同一目录 → 对比清单(允许新增 `thumb_cache/`,不允许缺失/改名/改格式);③ 新版添加 folder + 索引 → 旧 Qt 版再启动能读同一 DB/faiss 并正常搜索;结论写入 `docs/mobile-folder/[dev]webui-refactor-data-compat-checklist.md`。
- [ ] **Step 4:** `uv run bash scripts/run_tests.sh` 全绿。
- [ ] **Step 5: Commit** `feat: package shell+index server, switch default entry, data-compat acceptance`

> 备注(下一期入口):`tools/dts_dispatcher.py`、`base/status_bar_messenger.py` 及全部 Qt UI 文件(`view/`、`base/` Qt model、`browse/` Qt model)在 mobile 迁移完成后随 PySide6 依赖一并删除;本期它们保持冻结、仅作为回退入口。
