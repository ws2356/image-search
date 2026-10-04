# AuSearch 桌面端 Web UI 重构设计

- 日期: 2026-10-04
- 状态: 待评审
- 范围: `dt_image_search` 主 UI 由 PySide6/Qt 迁移为 Vue3 Web UI;索引/查询等核心逻辑拆分到独立 index server 进程;WebUI 与 index server 通过 HTTP + WebSocket 通信。

## 背景与目标

现状:Qt(PySide6)主窗口进程内直接调用控制器(`SearchController`/`BrowseController`),控制器再直接调用 `dts_index`(FAISS + OpenCLIP)、`dts_db`(SQLite),事件用 Qt Signal + `dts_event_bus`。

目标:
1. 主 UI 用 Vue3 重写,由 index server 静态托管,通过 HTTP(API/缩略图/原图)+ WebSocket(实时事件)渲染页面。
2. 索引、查询、DB 等核心逻辑全部收敛到独立 index server 进程(壳进程不含模型与业务)。
3. 彻底移除 PySide6/Qt 依赖。
4. mobile-folder 迁移到下一期,本期不做(见范围约束)。

## 决策记录

| # | 决策 | 理由 |
|---|------|------|
| D1 | 壳技术选 **pywebview**(纯 Python 栈) | 与现有 Python 代码复用最高,打包链不变,避免引入 Rust(Tauri)或 Node 栈(Electron) |
| D2 | **壳与 index server 拆两个进程**,index server 为壳的子进程 | torch/FAISS 需独立启动环境变量;native crash 不连坐 UI;壳可先显示 loading 页再等 server 就绪,启动体验更好;HTTP+WS 边界本来必须存在,拆进程边际成本极小 |
| D3 | 复用核心模块(`dts_index`/`dts_db`/worker 等),**不重写** | 这些模块本身不依赖 Qt 主线程;回归风险低,可沿用现有单测 |
| D4 | mobile-folder **推迟到下一期**;本期 web UI 不含 mobile 功能 | 先完成主流程重构,缩小首期范围与风险 |
| D5 | Qt 相关的 `dts_dispatcher`/`status_bar_messenger` **直接删除**,不抽接口保留 | 无 Qt 后无 Qt 消费者;进程内事件统一走 EventBridge → WS |
| D6 | 打包形态锁死**单 .app bundle(macOS)/ 单安装目录(Windows),index server 为壳的子进程** | TCC 权限归属同一签名身份,shell 选目录 → server 访问自动共享,无需权限转移机制 |

## 兼容性约束(必须满足)

1. **数据格式完全不变**:app data 目录路径、`app_data.sqlite` 及 schema、每 folder 的 `*.faiss` 文件、`model_cache/` 缓存结构与文件名、`app_config` 键值,全部保持与现版本一致。重构后应能直接用旧数据目录启动,且可回退到 Qt 版本读取同一数据。
2. **行为兼容**:folder 状态机(0 scanning/1 indexing/2 indexed/3 partial)、文件 status 语义、normalize 后的路径格式不变。
3. mobile-folder 相关代码保留但不在本期接线;相关表结构(`ensure_mobile_pairing_schema`)照旧执行,不得破坏。

## 目标架构

```
┌──────────────────────── 壳进程 (shell, pywebview) ────────────────────────┐
│  托盘(pystray) + 单实例锁 + macOS App 菜单(PyObjC 少量代码)                │
│  pywebview 窗口: 先加载 loading 页 → 收到 server ready 后加载             │
│  http://127.0.0.1:<port>/                                                 │
│  系统对话框桥: create_file_dialog(选目录) / reveal in Finder               │
└───────────────────────────────┬───────────────────────────────────────────┘
                                │ 子进程 stdio 握手(port + 一次性 token)
┌───────────────────────────────▼── Index server 进程 ──────────────────────┐
│  FastAPI (HTTP + WebSocket), 仅监听 127.0.0.1, WS 校验 token              │
│  ├─ 静态托管 webui/dist (Vue3 构建产物)                                    │
│  ├─ 服务层(复用): dts_index / dts_db / index_worker /                     │
│  │   incremental_index_worker / image_processor / bm_fs_monitor           │
│  └─ EventBridge: dts_event_bus(default_bus) 事件 → WS 消息(带 schema)      │
│       Qt 的 dispatcher / status_bar_messenger 直接删除                     │
└───────────────────────────────┬───────────────────────────────────────────┘
                                │ app_data.sqlite(WAL)+ 每 folder 一个 faiss
┌───────────────────────────────▼── WebUI (Vue3 + Vite + Pinia) ────────────┐
│  页面: 搜索 / 浏览(文件夹树+缩略图网格) / 图片查看器 / 设置                 │
│  UI 不做业务计算;实时状态全部来自 WS 推送                                   │
└───────────────────────────────────────────────────────────────────────────┘
```

关键约束:
- **index server 是唯一写库/写索引的进程**(SQLite + faiss 文件独占访问,保留 WAL)。
- 壳/通过子进程 stdio 握手交换 port 与一次性 token;WS 连接校验 token。
- 现有 `get_app_data_path()` 的 env-var 跨进程共享机制沿用。

## 进程与权限模型(macOS TCC)

- 非 sandbox 的 DMG 分发(现状)下,TCC 授权归属 app bundle(签名身份),不按进程划分;同 bundle 内 shell 选目录后,index server 访问同一目录自动被同一授权覆盖,**无权限分离问题**。
- 已知体验细节:TCC 弹窗可能出现在 server 首次实际索引受保护目录(桌面/文稿/下载)时,而非选目录瞬间;一次确认后永久有效,在 FAQ 中说明。
- 约束:index server 必须由壳拉起(子进程),不得作为用户手动启动的独立可执行文件。
- 未来升级路径(暂不实现,YAGNI):若走 App Store(sandbox),shell 在 `NSOpenPanel` 回调中生成 security-scoped bookmark 传给 server resolve(`startAccessingSecurityScopedResource`)。
- Windows/Linux:无文件权限模型,路径明文传递,无此问题。

## Qt 依赖移除清单

| Qt 提供的能力 | 替代方案 |
|---------------|----------|
| 主窗口/任务栏/Dock 图标 | pywebview 原生窗口(系统默认行为,零成本) |
| 系统托盘图标+菜单 | pystray |
| macOS 顶部 App 菜单 | PyObjC 少量代码(macOS-only 模块,如 `shell/macos_menu.py`),只留 About/设置/退出/显示窗口;Windows/Linux 不加载 |
| 选文件夹对话框 | pywebview `create_file_dialog`(原生 NSOpenPanel/IFileDialog) |
| reveal in Finder / 资源管理器 | subprocess 系统命令(`open -R` / `explorer /select,` / `xdg-open`) |
| `dts_dispatcher` / `status_bar_messenger` | 删除;事件统一走 EventBridge → WS |

## API 与事件设计

HTTP(幂等/请求-响应):

| 接口 | 功能与适用场景 |
|------|----------------|
| `GET /folders` | 列出全部 folder 及状态;浏览页/搜索页初始化时拉取 |
| `POST /folders {path}` | 添加 folder 入库并入队索引;用户选择目录后调用 |
| `DELETE /folders/{id}` | 移除 folder 及其索引;对齐现 Qt 版的 folder 删除行为 |
| `POST /folders/{id}/reindex` | 对指定 folder 重建索引;索引进度异常/手工触发重建时用 |
| `GET /search?q=&limit=` | 跨 folder 合并检索,返回 file+score;搜索页输入防抖后调用 |
| `GET /browse?folder_id=&path=` | 按 folder/子路径列出文件;浏览页翻页/进入子目录时调用 |
| `GET /thumb/{fileId}` | 缩略图(磁盘缓存 + 内存 LRU);网格/列表缩略图直接 `<img>` 加载 |
| `GET /file/{fileId}` | 原图流;图片查看器打开大图时调用 |
| `GET /status` | 模型加载状态 + 各 folder 索引进度汇总;启动页与设置页轮询/兜底 |
| `POST /shell/pick-folder` | 转发壳进程弹出系统选目录对话框;添加 folder 流程第 1 步 |
| `POST /shell/reveal {fileId}` | 转发壳进程在 Finder/资源管理器中显示文件;结果项右键/按钮用 |

WebSocket `/events`(服务端推送,统一信封 schema):
- `index_progress` / `status_message` / `fs_changed` / `model_load_failed`
- mobile 相关事件在下一期 mobile 迁移时随实现补充。

## 打包与构建

- 新增目录:`dt_image_search/index_server/`(FastAPI 入口 `main.py`)、`dt_image_search/shell/`(pywebview+托盘入口 `shell_main.py`)、`dt_image_search/webui/`(Vue3 工程)。
- 构建链:`pnpm run build` 产出 `webui/dist`;`build_pyinstaller.sh` 打包为双入口(壳为 onefile/onedir 主程序,index server 作为其内嵌资源,由壳以子进程方式释放/启动为同 bundle 可执行),静态资源打包进 server。
- 依赖变化:移除 PySide6;新增 pywebview、pystray(macOS 上复用运行时 PyObjC)。

## 测试策略

- 复用现有核心模块单测(`tests/unit/`,重依赖已 mock),改造因删除 Qt dispatcher/status messenger 受影响的用例。
- 新增 FastAPI TestClient 集成测试:API 行为 + 对核心模块的装配。
- EventBridge 事件 schema 契约测试(确保 WS 消息与 WebUI 期望一致)。
- **数据兼容验证**:用既有 app data 目录分别启动新旧版本,确认 schema/路径/faiss 文件零差异。

## 改动步骤

1. **拆除 Qt 耦合点**:删除 `dts_dispatcher`/`status_bar_messenger` 等 Qt 专用线程派发/状态栏组件;controller 类改为不依赖 Qt 主线程的事件回调;为 controller 类补无 Qt 单测。
2. **搭建 index server 骨架**:`index_server/main.py`(FastAPI + 仅 127.0.0.1 + token 校验 + 静态托管占位),接入 search/browse/folder/thumb/status API,复用现有模块;补 TestClient 集成测试与数据兼容验证。
3. **搭建 webui 骨架**:`webui/` Vue3 + Vite + Pinia(pnpm 管理);实现搜索页、浏览页、缩略图加载三件套,先 mock 数据开发再对接真实 server。
4. **EventBridge**:`default_bus` 事件 → WS 推送;WebUI 实时显示索引进度/状态消息;schema 契约测试。
5. **文件夹选择桥**:壳 `create_file_dialog` → `POST /shell/pick-folder` → server `POST /folders` 全链路;reveal-in-Finder 走壳。
6. **壳进程**:pywebview 窗口 + loading→ready 握手 + pystray 托盘 + 单实例锁 + macOS 菜单(PyObjC)。
7. **打包与清理**:更新 `build_pyinstaller.sh` 双进程打包;验证 DMG/MSIX 与数据兼容;确认功能对齐后把 Qt UI 标记为待删除并清理 `requirements.txt`。

每步完成即提交(带 `[LLM: glm-5.3-flash]`)并保证 `scripts/run_tests.sh` 通过。
