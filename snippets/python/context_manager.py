"""Context managers: the @contextmanager shortcut and the class version.

Rule of thumb: use @contextmanager unless you need to reuse the object or add
methods to it. The class form is more verbose but clearer when there's real
state to manage.

Run: python context_manager.py
"""

from __future__ import annotations

import sqlite3
import time
from collections.abc import Iterator
from contextlib import contextmanager


@contextmanager
def timer(label: str) -> Iterator[None]:
    """Time a block. Prints even if the block raises.

    Anything before the yield is setup, after is teardown. Wrap the yield in
    try/finally if the teardown must always run.
    """
    start = time.perf_counter()
    try:
        yield
    finally:
        elapsed = (time.perf_counter() - start) * 1000
        print(f"[timer] {label}: {elapsed:.1f} ms")


@contextmanager
def transaction(conn: sqlite3.Connection) -> Iterator[sqlite3.Cursor]:
    """Commit on success, roll back on any exception.

    This is the whole reason I keep this file around. Doing commit/rollback by
    hand means one day you forget the rollback and leave a half-written row in
    the DB.
    """
    cur = conn.cursor()
    try:
        yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()


class TempEnv:
    """Class-based manager: temporarily set os.environ keys.

    Class form is worth it here because we keep state (the old values) and it's
    nice to have it as a named object you can pass around.
    """

    def __init__(self, **overrides: str) -> None:
        self._overrides = overrides
        self._saved: dict[str, str | None] = {}

    def __enter__(self) -> "TempEnv":
        import os

        self._os = os
        for key, value in self._overrides.items():
            self._saved[key] = os.environ.get(key)
            os.environ[key] = value
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        for key, old in self._saved.items():
            if old is None:
                self._os.environ.pop(key, None)
            else:
                self._os.environ[key] = old
        # Returning False (falsy) means "don't swallow the exception".
        return False


def main() -> None:
    with timer("sleep 0.05"):
        time.sleep(0.05)

    conn = sqlite3.connect(":memory:")
    with transaction(conn) as cur:
        cur.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        cur.execute("INSERT INTO t (name) VALUES (?)", ("alice",))

    # A failing transaction should roll back and leave the table empty.
    try:
        with transaction(conn) as cur:
            cur.execute("INSERT INTO t (name) VALUES (?)", ("bob",))
            raise RuntimeError("pretend the network died")
    except RuntimeError as exc:
        print("rolled back:", exc)

    rows = conn.execute("SELECT name FROM t").fetchall()
    print("rows after rollback:", rows)  # only alice
    conn.close()

    import os

    with TempEnv(APP_ENV="test", DEBUG="1"):
        print("inside:", os.environ.get("APP_ENV"), os.environ.get("DEBUG"))
    print("outside APP_ENV:", os.environ.get("APP_ENV"))  # None again


if __name__ == "__main__":
    main()
