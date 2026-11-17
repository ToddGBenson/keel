# Self-review — TheHub #61385 (no test suite inside a production container)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #190   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
verdict: pass

`docker exec` runs a command INSIDE the production container, under none of the --cpus/--memory caps
a test container gets. Uncapped test runs on the operator's host took TheHub production down on
2026-10-23 (TheHub #61001). Until now nothing stopped an agent running
`docker exec thehub-backend pytest`.

## The change

- guard-bash.sh refuses `docker exec` or `docker container exec` into thehub-backend,
  thehub-postgres or mykronos-backend when the same exec runs `pytest`, `py.test`,
  `python[N] [-flags] -m pytest`, `tox` or `nox`. Any options before the container are covered,
  and so are a runner by path, under `nice`, or inside `sh -c '...'` (the masked word view).
- The refusal names the route: a capped test container (`--cpus 2 --memory 2g`) through TheHub's
  shared lock, `bash scripts/docker-test-lock.sh run <owner> -- bash scripts/test-offline.sh ...`.
- docs/11-ai-agent-controls.md has a row for it, including what is not caught.

## Verified independently

- **Red first:** the 15 new selftest cases against main c7ba09e's hook: all 10 must-block cases
  were ALLOWED (pytest, `python -m pytest`, `python3 -u -m pytest`, tox in mykronos-backend, nox in
  thehub-postgres, pytest by path, inside `sh -c`, `docker container exec`, under `nice`, and the
  PowerShell tool). The 5 must-allow cases passed.
- **Green after:** selftest 320 passed / 0 failed (305 + 15). The must-allow cases still pass:
  `docker exec thehub-backend cat /proc/loadavg`, `cat /app/pytest.ini`, pytest in a non-production
  container, a capped `docker run --cpus 2 --memory 2g ... pytest`, and `docker exec ... cat x;
  pytest` (pytest on the host).
- **First attempt caught by the red/green:** the boundary after the container name consumed the
  space that the runner's boundary needed. Plain `pytest` after the container was missed while
  `/usr/local/bin/pytest` was caught (5 failures). The pattern now takes one boundary character,
  then optionally anything and a second boundary.
- **No regressions:** bypass corpus 224 entries, 804 hook runs, 0 failed. hook-fail-closed.test.py
  all passed. `./keel check` green in a capped python:3.12-slim container. shellcheck v0.10.0
  `-S warning` clean. Pinned gitleaks v8.18.4: no leaks.

## Not in this story

- The capacity-incident AC is TheHub-side and is not built here.

## Not verified

- Git Bash on Windows was not run. The rule is a plain ERE on the same views as every other rule.
- A runner started under another name (a script or Makefile target that calls pytest), a container
  reached by id or renamed, or `docker compose exec backend` by service name, is not caught. These
  are listed in the controls row.

## Residual risk accepted

The gaps above. This is a denylist over command text, like every guard-bash.sh rule.
