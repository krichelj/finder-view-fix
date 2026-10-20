#!/bin/bash
# Independent edge-case suite. Multiprocessing: pytest-xdist spreads test
# files/cases over all cores (-n auto); several tests additionally use
# ThreadPoolExecutor / ProcessPoolExecutor internally.
cd "$(dirname "$0")"
exec uv run --quiet --with pytest --with pytest-xdist --with ds-store \
  python -m pytest -q -n auto -p no:cacheprovider "$@" .
