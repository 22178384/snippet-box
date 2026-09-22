"""几个实用装饰器。"""


def timing(func):
    import time

    def wrapper(*a, **k):
        t = time.perf_counter()
        try:
            return func(*a, **k)
        finally:
            print(f"{func.__name__} 耗时 {time.perf_counter() - t:.4f}s")
    return wrapper


def singleton(cls):
    instances = {}

    def get(*a, **k):
        if cls not in instances:
            instances[cls] = cls(*a, **k)
        return instances[cls]
    return get
