# bar-tab

bar-tab is a self-hosted tab ("Strichliste") for small clubs and associations: members
or bar staff book drinks on a shared tablet, and the server keeps the running tabs,
closes billing periods and sends monthly reports. It replaces paper lists with a simple,
offline-tolerant tablet app (Flutter) backed by a small Python service (FastAPI).

**Status:** under construction. Not usable yet.

## Development

Server tests, lint and format check run in Docker:

```sh
server/tool/test.sh            # pytest, ruff check, ruff format --check
server/tool/test.sh -k health  # extra arguments are passed to pytest
```

Copy `.env.example` to `.env` and adjust it for local runs. A full operator guide will follow.

## Licence

MIT, see [LICENSE](LICENSE).
