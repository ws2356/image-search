# AuSearch 桌面端 Web UI 重构设计

- 日期: 2026-10-04
- 状态: 待评审
- 范围: `dt_image_search` 主 UI 由 PySide6/Qt 迁移为 Vue3 Web UI;索引/查询等核心逻辑拆分到独立 agent 进程;WebUI 与 agent 通过 HTTP + WebSocket 通信。

## 背景与目标

现状:Qt(PySide6)主窗口进程内直接调用控制器(`SearchController`/`BrowseController`),控制器再直接调用 `dts_index`(FAISS + OpenCLIP)、`dts_db`(SQLite),事件用 Qt Signal + `dts_event_bus`。

目标:
1. 主 UI 用 Vue3 重写,由 agent 静态托管,通过 HTTP(API/缩略图/原图)+ WebSocket(实时事件)渲染页面。
2. 索引、查询、DB 等核心逻辑全部收敛到独立 agent 进程(与无 model 的壳无关)。
3. 彻底移除 PySide6/Qt 依赖。

## 决策记录

| # | 决策 | 理由 |
|---|------|------|
| D1 | 壳技术选 **pywebview**(纯 Python 栈) | 与现有 Python 代码复用最高,打包链不变,避免引入 Rust(Rust/Tauri)或 Node 栈(Electron) |
| D2 | **壳与 agent 拆两个进程**,agent 为壳的子进程 | torch/FAISS 需独立启动环境变量;native crash 不连坐 UI;壳可先显示 loading 页再等 agent 就绪,启动体验更好;HTTP+WS 边界本来必须存在,拆进程边际成本极小 |
| D3 | 复用核心模块(`dts_index`/`dts_db`/worker 等),**不重写** | 这些模块本身不依赖 Qt 主线程;回归风险低,可沿用现有单测 |
| D4 | mobile-folder 功能**全量迁入** web UI | 按 2026-10-04 决定;子系统与 UI 解耦较好,状态机直接随 agent 运行 |
| D5 | Qt 相关的 `dts_dispatcher`/`status_bar_messenger` **直接删除**,不抽接口保留 | 无 Qt 后无 Qt 消费者;进程内事件统一走 EventBridge → WS,保持"one way to do things" |
| D6 | 打包形态锁死**单 .app bundle(macOS)/ 单安装目录(Windows),agent 为壳的子进程** | TCC 权限归属同一签名身份,shell 选目录 → agent 访问自动共享,无需权限转移机制 |

## 目标架构

```
┌──────────────────────── 壳进程 (shell, pywebview) ────────────────────────┐
│  托盘(pystray) + 单实例锁 + macOS App 菜单(PyObjC 少量代码)                │
│  pywebview 窗口: 启动实测先加载 loading 页 → 收到 agent ready 后加载       │
│  http://127.0.0.1:<port>/                                                 │
│  系统对话框桥: create_file_dialog(选目录) / reveal in Finder               │
└───────────────────────────────┬───────────────────────────────────────────┘
                                │ 子进程 stdio 握手(port + 一次性 token)
┌───────────────────────────────▼── Agent 进程 (server) ────────────────────┐
│  FastAPI (HTTP + WebSocket), 仅监听 127.0.0.1, WS 校验 token              │
│  ├─ 静态托管 webui/dist (Vue3 构建产物)                                    │
│  ├─ 服务层(复用): dts_index / dts_db / index_worker /                     │
│  │   incremental_index_worker / image_processor / bm_fs_monitor /         │
│  │   mobile/* 状态机                                                      │
│  └─ EventBridge: dts_event_bus(default_bus) 事件 → WS 消息(带 schema)      │
│       依赖 Qt 的 dispatcher / status_bar_messenger 直接删除                 │
└───────────────────────────────┬───────────────────────────────────────────┘
                                │ app_data.sqlite(WAL)+ 每 folder 一个 faiss
┌───────────────────────────────▼── WebUI (Vue3 + Vite + Pinia) ────────────┐
│  页面: 搜索 / 浏览(文件夹树+缩略图网格) / 图片查看器 / 设置 / mobile 备份    │
│  UI 不做业务计算;实时状态全部来自 WS 推送                                   │
└───────────────────────────────────────────────────────────────────────────┘
```

关键约束:
- **agent 是唯一写库/写索引的进程**(SQLite + faiss 文件独占访问,保留 WAL)。
- 壳/agent 通过子进程 stdio 握手交换 port 与一次性 token;WS 连接校验 token。
- 现有 `get_app_data_path()` 的 env-var 跨进程共享机制沿用。

## 进程与权限模型(macOS TCC)

- 非 sandbox 的 DMG 分发(现状)下,TCC 授权归属 app bundle(签名身份),不按进程划分;同 bundle 内 shell 选目录后,agent 访问同一目录自动被同一授权覆盖,**无权限分离问题**。
- 已知体验细节:TCC 弹窗可能出现在 agent 首次实际索引受保护目录(桌面/文稿/下载)时,而非选目录瞬间;一次确认后永久有效,在 FAQ 中说明。
- 约束:agent 必须由壳拉起(子进程),不得作为用户手动启动的独立可执行文件。
- 未来升级路径(暂不实现,YAGNI):若走 App Store(sandbox),shell 在 `NSOpenPanel` 回调中生成 security-scoped bookmark 传给 agent resolve(`startAccessingSecurityScopedResource`)。
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
- `GET /folders`、`POST /folders {path}`、`DELETE /folders/{id}`、`POST /folders/{id}/reindex`
- `GET /search?q=&limit=`(跨 folder 合并后的 file+score 列表)
- `GET /browse?folder_id=&path=`
- `GET /thumb/{fileId}`(缩略图,磁盘缓存 + 内存 LRU)、`GET /file/{fileId}`(原图,查看器用)
- `GET /status`(模型加载状态、各 folder 索引进度汇总)
- `POST /shell/pick-folder`、`POST /shell/reveal {fileId}`:agent 转发到壳进程执行系统对话框/路径展示

WebSocket `/events`(服务端推送,统一信封 schema):
- `index_progress` / `status_message` / `fs_changed` / `model_load_failed` / `mobile_transfer_*`

## Mobile-folder 迁移

- `mobile/` 子系统(pairing / 传输 / AOA-USB / 状态机)保持 `docs/mobile-folder/` 的协议与 spec 不变,随 agent 进程运行。
- UI 由 Qt 面板改为 Vue 页面(备份面板、传输进度、配对流程);传输事件经由 EventBridge 推送 WS。

## 打包与构建

- 新增目录:`dt_image_search/agent/`(FastAPI 入口 `agent_main.py`)、`dt_image_search/shell/`(pywebview+托盘入口 `shell_main.py`)、`dt_image_search/webui/`(Vue3 工程)。
- 构建链:`npm run build` 产出 `webui/dist`;`build_pyinstaller.sh` 打包为双入口(壳为 onefile/onedir 主程序 + agent 作为其内嵌资源,由壳以子进程方式释放/启动为同 bundle 可执行),静态资源打包进 agent。
- 依赖变化:移除 PySide6;新增 pywebview、pystray(macOS 上复用运行时 PyObjC)。

## 测试策略

- 复用现有核心模块单测(`tests/unit/`,重依赖已 mock),改造因删除 Qt dispatcher/status messenger 受影响的用例。
- 新增 FastAPI TestClient 集成测试:API 行为 + 对核心模块的装配。
- EventBridge 事件 schema 契约测试(确保 WS 消息与 WebUI 期望一致)。

## 改动步骤

1. **拆除 Qt 耦合点**:删除 `dts_dispatcher`/`status_bar_messenger` 等 Qt 专用线程派发/状态栏组件;controller 类改为不依赖 Qt 主线程的事件回调;为 controller 类补无 Qt 单测。
2. **搭建 agent 骨架**:`agent/agent_main.py`(FastAPI + 仅 127.0.0.1 + token 校验 + 静态托管占位),首先接入 search/browse/folder/thumb 4 类 API,复用现有模块;补 TestClient 集成测试。
3. **搭建 webui 骨架**:`webui/` Vue3 + Vite + Pinia;实现搜索页、浏览页、缩略图加载三件套,走 mock 数据开发再对接真实 agent。
4. **EventBridge**:`default_bus` 事件 → WS 推送;WebUI 实时显示索引进度/状态消息;schema 契约测试。
5. **文件夹选择桥**:壳 `create_file_dialog` → `POST /shell/pick-folder` → agent `POST /folders` 全链路;reveal-in-Finder 走 shell。
6. **mobile-folder 迁移**:状态机随 agent 运行,Vue 备份面板/传输进度/配对 UI;回归 `mobile` 传输相关单测。
7. **壳进程**:pywebview 窗口 + loading→ready 握手 + pystray 托盘 + 单实例锁 + macOS 菜单(PyObjC)。
8. **打包与清理**:更新 `build_pyinstaller.sh` 双进程打包;验证 DMG/MSIX;确认功能对齐后把 Qt UI 标记为待删除并清理 `requirements.txt`。

每步完成即提交(带 `[LLM: glm-5.3-flash]`)并保证 `scripts/run_tests.sh` 通过。
