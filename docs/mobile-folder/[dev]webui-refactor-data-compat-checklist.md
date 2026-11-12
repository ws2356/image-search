# Web UI 重构 — 数据兼容验收清单

Spec: `docs/superpowers/specs/2026-10-04-web-ui-refactor-design.md`(兼容性约束一节)
原则:app data 路径、`app_data.sqlite` schema、`*.faiss` 文件名/格式、`model_cache/` 结构、`app_config` 键值**完全不变**;唯一允许的新增是 `thumb_cache/` 子目录。

## 环境准备

```bash
# 1. 安装仓库已锁定的依赖:
uv sync --frozen

# 2. 构建 web UI(如尚未构建):
pnpm -C dt_image_search/webui install && pnpm -C dt_image_search/webui build
```

## 步骤 A:记录基线(旧 Qt 版)

```bash
uv run --frozen python -m dt_image_search   # Qt 版入口(回退入口,保持可启动)
# 在 Qt UI 里对任一已有 folder 做一次搜索,确认正常,然后退出。
```

记录 app data 目录(QStandardPaths 实际解析:`~/Library/Application Support/net.boldman/imagesearch[-dev]/DTImageSearch[-dev]`;dev 构建为 `-dev` 段):

```bash
APP_DATA="$HOME/Library/Application Support/net.boldman/imagesearch/DTImageSearch"
find "$APP_DATA" -maxdepth 1 | sort > /tmp/before-files.txt
sqlite3 "$APP_DATA/app_data.sqlite" "SELECT key, value FROM app_config ORDER BY key;" > /tmp/before-config.txt
sqlite3 "$APP_DATA/app_data.sqlite" "SELECT id, path, status FROM folders ORDER BY id;" > /tmp/before-folders.txt
sqlite3 "$APP_DATA/app_data.sqlite" ".schema" > /tmp/before-schema.txt
ls -la "$APP_DATA"/*.faiss > /tmp/before-faiss.txt
```

## 步骤 B:新壳版同一数据目录

```bash
bash scripts/run_app.sh   # 默认入口 = pywebview 壳 + index server
# 冒烟清单(Task 13):
#  1. 启动:先出现"正在启动…"加载页,数秒后进入 Vue UI
#  2. 浏览页能看到旧版已有的 folder 列表(状态徽标正确)
#  3. 搜索页能搜出旧版已索引内容(共享 faiss 生效)
#  4. 点"添加文件夹"(原生目录对话框)→ 新 folder 出现,索引进度横幅实时刷新
#  5. 点击缩略图进入查看器,←/→ 导航,"在文件管理器中显示"可用
#  6. 设置页显示模型状态与 folder 状态表
#  7. 托盘(Win/Linux)/App 菜单(macOS):退出按钮可退出
#  8. server 崩溃重启:kill AuSearchIndexServer 后 UI 自动恢复(重连后状态刷新)
```

验收后对比:

```bash
APP_DATA="$HOME/Library/Application Support/net.boldman/imagesearch/DTImageSearch"
find "$APP_DATA" -maxdepth 1 | sort > /tmp/after-files.txt
sqlite3 "$APP_DATA/app_data.sqlite" "SELECT key, value FROM app_config ORDER BY key;" > /tmp/after-config.txt
sqlite3 "$APP_DATA/app_data.sqlite" ".schema" > /tmp/after-schema.txt
ls -la "$APP_DATA"/*.faiss > /tmp/after-faiss.txt

diff /tmp/before-files.txt /tmp/after-files.txt      # 只允许出现 thumb_cache/
diff /tmp/before-config.txt /tmp/after-config.txt    # 应为空(model_version 等不得漂移)
diff /tmp/before-schema.txt /tmp/after-schema.txt    # 必须为空
```

## 步骤 C:新写数据旧版可读(双向)

在新壳版里添加一个新 folder 并等索引完成(status=2),然后:

```bash
uv run --frozen python -m dt_image_search   # 再次启动 Qt 版
# Qt 版应能:列出该新 folder、搜索出其内容、浏览缩略图正常
```

## 结果记录

| 步骤 | 结论 | 日期 | 备注 |
|------|------|------|------|
| A 基线 | ☐ 待执行 | | |
| B 新壳冒烟(8 项) | ☐ 待执行 | | |
| B 数据 diff | ☐ 待执行 | | |
| C 双向可读 | ☐ 待执行 | | |

执行人/日期:__________

## 自动化补充验证(2026-11-13)

以下结果来自 macOS dev 打包产物与既有 app data 的隔离副本,不替代上表的旧 Qt GUI 基线、完整 GUI 操作及双向兼容验收。

- 产物:`/tmp/ausearch-webui-refactor-20261113/AuSearch-dev.app`;PyInstaller 构建成功,壳和 `AuSearchIndexServer` 均正常启动。另行确认 Cocoa 原生菜单包含 About、Quit 和“显示窗口”。
- 原始数据复制到临时目录,SQLite 使用 backup API 生成一致副本;通过数据路径环境变量让打包产物仅使用该副本。
- 启动后数据库 schema、`app_config` 内容及两个既有 FAISS 文件的 SHA-256 均与副本基线相同,数据目录根部未新增条目。模型达到 ready,旧 folder 列表可读取。
- 两个旧 FAISS 索引在基线中均为空,旧数据搜索响应为 200、结果为空;这不能证明旧版已索引内容在新版可搜索。
- 向测试目录添加两张图片后,新增 folder 返回 201,索引最终达到 status=2;浏览返回两张图片,缩略图及原图均返回 200,搜索返回结果,新 FAISS 文件可由 FAISS 读取。
- 未认证 SPA/docs 请求返回 401,认证 SPA 请求及 health 返回 200;终止 sidecar 后壳自动重启一次,新 server 的 `/status` 返回 200。
- 原始 JSON 报告:`/tmp/webui-refactor-packaged-smoke.json`;以上路径是本次本机临时产物,不作为仓库长期测试资源。

## 已知限制(本期)

- macOS 无托盘图标(pystray 需主线程,与 webview 冲突);Windows/Linux 有托盘。
- MSIX(Windows)打包适配未验证(见 `package_msix.ps1` TODO)。
- PyInstaller 打包构建需在无沙箱环境执行:`bash dt_image_search/scripts/build_pyinstaller.sh`。
