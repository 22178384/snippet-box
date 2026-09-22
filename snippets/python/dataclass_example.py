"""dataclasses: defaults, validation, ordering, and immutability.

The thing that trips people up is `field(default_factory=list)`. A plain
`= []` as a default is a classic Python bug (the list is shared between all
instances). dataclasses actually raises for mutable defaults, which is nice.

Run: python dataclass_example.py
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, replace
from datetime import datetime, timezone


@dataclass(order=True, frozen=True)
class Version:
    """Semver-ish version. frozen => hashable, so it can go in a set/dict key.

    order=True gives you <, >, <= ... for free, comparing field by field in
    declaration order. So (1, 2, 3) < (1, 3, 0). That's what you want for
    versions.
    """

    major: int
    minor: int
    patch: int

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @classmethod
    def parse(cls, text: str) -> Version:
        parts = text.split(".")
        if len(parts) != 3:
            raise ValueError(f"not a version: {text!r}")
        return cls(*(int(p) for p in parts))


@dataclass
class Article:
    title: str
    # default_factory, not a bare [] — see the docstring at the top of the file.
    tags: list[str] = field(default_factory=list)
    body: str = ""
    # repr=False keeps long bodies out of the auto-generated __repr__.
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    views: int = field(default=0, repr=False)

    def __post_init__(self) -> None:
        """Validation hook. Called right after __init__.

        Raise here for bad input. I prefer this over validating in a separate
        method because you can't forget to call it.
        """
        self.title = self.title.strip()
        if not self.title:
            raise ValueError("title must not be empty")
        if self.views < 0:
            raise ValueError("views cannot be negative")
        # Normalize tags: strip, lowercase, dedupe, keep original order.
        # dict.fromkeys is the shortest order-preserving dedupe in Python.
        cleaned = (t.strip().lower() for t in self.tags)
        self.tags = list(dict.fromkeys(t for t in cleaned if t))


def main() -> None:
    a = Article(title="  Hello World  ", tags=["Python", "python", " ", "Tips"])
    print(repr(a))            # note the trimmed title and deduped tags
    print("tags:", a.tags)

    # replace() makes a copy with some fields changed. Doesn't mutate `a`.
    b = replace(a, views=10)
    print("b.views:", b.views, "a.views:", a.views)

    print("as dict:", {k: v for k, v in asdict(a).items() if k != "created_at"})

    # frozen + order
    v1, v2 = Version.parse("1.2.3"), Version.parse("1.10.0")
    print(f"{v1} < {v2} ?", v1 < v2)
    print("distinct versions:", len({v1, v2, Version(1, 2, 3)}))

    try:
        Article(title="   ")
    except ValueError as exc:
        print("caught:", exc)


if __name__ == "__main__":
    main()
