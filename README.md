# snippet-box

A box of code snippets I keep reaching for. Every file here is something I've
actually used or copied out of a project, not a textbook example. Comments are
in each language's usual style.

I got tired of grepping my own dotfiles and old repos for "that retry decorator"
or "that k8s deployment that actually worked", so now they live in one place.

## What's here

```
python/
  decorators.py         retry, timing, memoize, rate limit
  dataclass_example.py  dataclasses with validation and defaults
  context_manager.py    @contextmanager + a class-based one
bash/
  backup.sh             rsync backup with rotation and a lock file
  rotate_logs.sh        gzip + prune old logs
sql/
  window_functions.sql  running totals, ranking, lag/lead
go/
  http_server.go        net/http server with graceful shutdown
js/
  debounce.js           debounce + throttle, no lodash
rust/
  hello.rs              stdin -> stdout filter
yaml/
  k8s_deployment.yaml   deployment + service + probes
```

## How to use these

Copy the file, delete what you don't need. These are snippets, not a library, and
I'm not going to package them. There's no `setup.py`, no `package.json`, nothing
to install.

For the shell scripts, make them executable first:

```bash
chmod +x snippets/bash/backup.sh
snippets/bash/backup.sh --help
```

## Requirements

- Python 3.10+ (`decorators.py` uses `functools.wraps` and type hints; works on 3.9 too, actually)
- Go 1.21+ (`http_server.go` uses `slog`, which landed in 1.21)
- Node 18+ if you want to run `debounce.js` (it's plain ESM, no deps)
- Rust 1.70+ (`hello.rs` uses `let-else`, stabilized in 1.65)
- PostgreSQL 12+ for the window functions (`GROUPS` frame needs 11+)
- kubectl / a cluster for the YAML

## Gotchas

- **`backup.sh` uses `set -euo pipefail`.** That's on purpose. If you source it
  into an interactive shell it'll change your shell's error behavior. Run it,
  don't source it.
- **`decorators.py`'s `retry` catches `Exception` by default.** That includes
  `KeyboardInterrupt`? No — `KeyboardInterrupt` is a `BaseException`, so Ctrl-C
  still works. But it will retry on things like `ValueError` that you probably
  want to fail fast on. Pass an explicit `exceptions=` tuple.
- **The k8s manifest has a placeholder image.** `image: ghcr.io/example/app:0.1.0`
  won't pull. Change it before `kubectl apply`.
- **`window_functions.sql` assumes a `sales` table.** It creates it at the top in
  a transaction you can roll back, so you can run the whole file in psql safely.

## Notes

Not every snippet is battle-tested. The Go and Rust ones I've compiled locally.
The SQL I've run against Postgres 16. If something's wrong, open an issue or
just fix your copy — I'm not precious about it.

MIT. See LICENSE.
