# asyncio 迁移约定(Web UI 重构)

本文是 AuSearch 桌面端 Web UI 重构引入的 asyncio 渐进迁移约定,对后续所有相关任务生效。

## 1. 范围

- index server 及其配套 Python 新代码 **async-first**。
- 既有同步核心(`dts_db` / `dts_index` / `index_worker` / `incremental_index_worker` / `image_processor` / `bm_fs_monitor`)**不重写**,通过边界规则调用。
- Qt 侧遗留代码不受本约定约束(待下一期 mobile 迁移时随 Qt 一起移除)。

## 2. 边界规则(只允许两种桥接)

| 方向 | 唯一写法 |
|------|----------|
| async → sync | `await asyncio.to_thread(fn, ...)`(service / `dts_db` 等同步调用在路由内经此包装) |
| sync → async | `broadcast_threadsafe`(EventBridge:`asyncio.run_coroutine_threadsafe` 投递到 uvicorn 主 loop) |

禁止再引入其他桥接方式(One Way To Do Things)。

## 3. 禁止事项

- 在 `async def` 内直接执行阻塞 I/O(文件、SQLite、subprocess、网络同步调用)。
- 在事件循环线程内调用 `asyncio.run(...)`。
- 在工作线程内自建事件循环并与主 loop 通信——必须走 `broadcast_threadsafe` 模式。

## 4. 演进方向

- 后续 Touch 到的同步模块,顺势逐步迁移 asyncio。
- mobile 迁移(下一期)时新代码同样 async-first。
