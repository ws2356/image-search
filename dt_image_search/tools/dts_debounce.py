import threading
import functools
import time

def debounce(wait):
    """装饰器：只有在上次调用 wait 秒后无新调用，才执行函数。"""
    def decorator(fn):
        @functools.wraps(fn)
        def wrapped(*args, **kwargs):
            def call_it():
                fn(*args, **kwargs)

            try:
                wrapped.timer.cancel()
            except AttributeError:
                pass

            wrapped.timer = threading.Timer(wait, call_it)
            wrapped.timer.start()
        return wrapped
    return decorator



def throttle(wait, key_name = None):
    """
    :param wait: 节流间隔（秒）
    :param key_name: 用于隔离状态的关键字参数名称（例如 'file_id'）
    """
    # 全局注册表，存储每个 key 对应的独立状态
    registry = {}
    registry_lock = threading.Lock()

    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            # 提取作为 key 的参数值
            kv = kwargs.get(key_name) if key_name else None
            if kv is None:
                # 如果没提供 key_name，则退化为普通调用或报错
                return fn(*args, **kwargs)

            # 获取或创建该 key 对应的私有状态
            with registry_lock:
                if kv not in registry:
                    registry[kv] = {
                        'last_run_time': 0,
                        'pending_args': None,
                        'pending_kwargs': None,
                        'timer': None,
                        'lock': threading.Lock()
                    }
                state = registry[kv]

            now = time.time()
            ready_to_run = False
            with state['lock']:
                # 更新当前 key 下的最新的参数
                state['pending_args'], state['pending_kwargs'] = args, kwargs
                
                elapsed = now - state['last_run_time']

                # 定义 Timer 到期后的执行逻辑
                def fire(target_key):
                    with registry[target_key]['lock']:
                        s = registry[target_key]
                        f_args, f_kwargs = s['pending_args'], s['pending_kwargs']
                        s['pending_args'] = s['pending_kwargs'] = None
                        s['timer'] = None
                        s['last_run_time'] = time.time()
                    fn(*f_args, **f_kwargs)

                # 情况 A: 冷却期已过且没有排队的任务
                if elapsed >= wait and state['timer'] is None:
                    state['last_run_time'] = now
                    state['pending_args'] = state['pending_kwargs'] = None
                    ready_to_run = True
                
                # 情况 B: 冷却期内，启动或维持单次 Timer
                else:
                    if state['timer'] is None:
                        remaining = wait - elapsed
                        # 传入 kv 确保 Timer 回调时能找到正确的槽位
                        state['timer'] = threading.Timer(remaining, fire, args=[kv])
                        state['timer'].start()
            if ready_to_run:
                return fn(*args, **kwargs)
            return None

        return wrapper
    return decorator

# # 用法示例
# @debounce(0.5)  # 500ms 内如果又调用，就重新计时
# def on_click(x, y):
#     print(f"点击位置：{x},{y}")
# 
# # 模拟多次快速调用
# for i in range(5):
#     on_click(i, i)
# # 0.5s 后只打印最后一次 on_click(4,4)
# 