import threading
import functools

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