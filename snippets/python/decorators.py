"""Decorators I use often enough to keep around.

Nothing clever. The retry one is the only one with real logic; the rest are
short. Run this file directly for a quick demo:

    python decorators.py
"""

from __future__ import annotations

import functools
import random
import time
from collections.abc import Callable
from typing import Any, TypeVar

F = TypeVar("F", bound=Callable[..., Any])


def retry(
    attempts: int = 3,
    delay: float = 0.5,
    backoff: float = 2.0,
    exceptions: tuple[type[BaseException], ...] = (Exception,),
) -> Callable[[F], F]:
    """Retry a function on failure with exponential backoff.

    delay is the first sleep; each retry multiplies it by backoff. So with the
    defaults you sleep 0.5s then 1.0s. The last attempt does not sleep, which is
    a detail people get wrong and then wonder why it takes an extra 2s.

    Note `exceptions` defaults to Exception. That is broad. If your function
    raises ValueError on bad input, you do NOT want to retry three times on it.
    Pass exceptions=(ConnectionError, TimeoutError) instead.
    """

    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            current_delay = delay
            for attempt in range(1, attempts + 1):
                try:
                    return func(*args, **kwargs)
                except exceptions:
                    if attempt == attempts:
                        raise  # out of tries, let it bubble up
                    time.sleep(current_delay)
                    current_delay *= backoff
            # Unreachable, but keeps type checkers happy.
            raise RuntimeError("retry: fell through the loop")

        return wrapper  # type: ignore[return-value]

    return decorator


def timed(func: F) -> F:
    """Print how long the function took. Handy during profiling."""

    @functools.wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        start = time.perf_counter()
        try:
            return func(*args, **kwargs)
        finally:
            # finally so we still report time if it raises.
            elapsed = time.perf_counter() - start
            print(f"[timed] {func.__name__} took {elapsed * 1000:.1f} ms")

    return wrapper  # type: ignore[return-value]


def memoize(func: F) -> F:
    """Cache results by positional args. Keyword args are NOT part of the key.

    That's a deliberate simplification: hashing kwargs is fiddly and I've never
    needed it. If you call f(1, x=2) and f(1, x=3) you'll get the wrong cached
    value. Don't use this on functions that take meaningful kwargs.
    """
    cache: dict[tuple[Any, ...], Any] = {}

    @functools.wraps(func)
    def wrapper(*args: Any) -> Any:
        if args not in cache:
            cache[args] = func(*args)
        return cache[args]

    wrapper.cache_clear = cache.clear  # type: ignore[attr-defined]
    return wrapper  # type: ignore[return-value]


def rate_limit(calls_per_second: float) -> Callable[[F], F]:
    """Block so the function is called at most N times per second.

    Simple token-less approach: remember the last call time and sleep the
    remainder. Fine for a single thread. For multi-threaded use you need a lock,
    otherwise two threads race and both sleep less than they should.
    """
    min_interval = 1.0 / calls_per_second

    def decorator(func: F) -> F:
        last_called = 0.0

        @functools.wraps(func)
        def wrapper(*args: Any, **kwargs: Any) -> Any:
            nonlocal last_called
            elapsed = time.perf_counter() - last_called
            if elapsed < min_interval:
                time.sleep(min_interval - elapsed)
            result = func(*args, **kwargs)
            last_called = time.perf_counter()
            return result

        return wrapper  # type: ignore[return-value]

    return decorator


if __name__ == "__main__":
    attempts = {"n": 0}

    @retry(attempts=5, delay=0.05, exceptions=(ValueError,))
    def flaky() -> str:
        attempts["n"] += 1
        if attempts["n"] < 3:
            raise ValueError(f"boom {attempts['n']}")
        return f"ok after {attempts['n']} tries"

    print(flaky())

    @timed
    def slow() -> int:
        time.sleep(0.1)
        return 42

    print(slow())

    @memoize
    def fib(n: int) -> int:
        return n if n < 2 else fib(n - 1) + fib(n - 2)

    print("fib(30) =", fib(30))  # instant thanks to the cache

    @rate_limit(5)
    def ping() -> None:
        print(f"  ping at {time.perf_counter():.3f}")

    for _ in range(3):
        ping()
