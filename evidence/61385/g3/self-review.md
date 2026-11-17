# Self-review — TheHub #61385 (no test suite inside a production container)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: #190   Pair: binnacle #86   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-17
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
- **Review round 1 (Fable 5.2 on 722e17a, BLOCKED on two points):**
  1. `docker compose exec` / `docker-compose exec` into TheHub's compose services `backend` and
     `postgres` was not caught. It is now, and `backend-staging` and `postgres-staging` stay allowed.
  2. This record said the compose gap was listed in the docs row, and it was not. The row and the
     record now agree: compose is covered, and the gaps listed in both are the same.
  Nits taken: docker's global options before the subcommand (`docker -H ... exec`, `compose -f
  ... exec`), and `docker.exe`, `/usr/bin/docker` and `docker-compose.exe` via normalize(), which
  rewrites docker and docker-compose to the bare name as it does gh, git and curl. Stdin or heredoc
  runners, versioned runner binaries and `python -m unittest` are documented as gaps. A bare
  `pytest` word inside a production exec is left as a safe-side false positive, per the review.

## Verified independently

- **Red first:** the 15 new selftest cases against main c7ba09e's hook: all 10 must-block cases
  were ALLOWED (pytest, `python -m pytest`, `python3 -u -m pytest`, tox in mykronos-backend, nox in
  thehub-postgres, pytest by path, inside `sh -c`, `docker container exec`, under `nice`, and the
  PowerShell tool). The 5 must-allow cases passed.
- **Green after:** selftest 320 passed / 0 failed (305 + 15).
- **Round 1, red first:** the 10 new cases (7 must-block, 3 must-allow) against the previous head
  722e17a: 7 failed. Compose exec backend, compose -f with exec -T, docker-compose exec postgres,
  `docker -H ... exec`, docker.exe, /usr/bin/docker and PowerShell compose were all ALLOWED. Against
  main: 16 failed. **Green:** selftest 330 passed / 0 failed. The must-allow cases still pass:
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
- These are not caught, and the controls row lists the same set: a runner fed on stdin or a heredoc;
  a runner under another name (`pytest-3`, a versioned binary, a script or Makefile target); `python -m
  unittest`; a container reached by id or renamed.

## Residual risk accepted

The gaps above. This is a denylist over command text, like every guard-bash.sh rule.
