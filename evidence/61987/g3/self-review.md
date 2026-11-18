# Self-review — TheHub #61987 (review nits on #190: normalize(), compose run, uncapped docker run)

Mode: solo (POAM-008); agent self-review, pending the independent review before merge
PR: (set when opened)   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-18
verdict: pass

## The change

- **normalize() adds the bare name; it never substitutes it.** It rewrote any word whose last path
  segment was gh, git, curl, docker or docker-compose to the bare name. So `gh api -X PUT
  repos/O/R/contents/bin/gh ...` became `gh api -X PUT gh ...`, the contents rule never saw
  `/contents/`, and a commit to the default branch was ALLOWED. The same happened to a quoted endpoint
  and to a curl URL ending in `/curl`.
  - Now the word stays and the name follows it (`/usr/bin/gh gh`). Every rule reads the name, and
    the endpoint survives. A bare, lower-case name is left alone.
  - The review suggested rewriting only in command position. That was not done, on purpose: command
    position needs a list of wrappers (sudo, env, nice, ...), and a binary path after any wrapper not
    on the list (`timeout 5 /usr/bin/gh pr merge`) would no longer be read. Adding the name
    keeps that case, and a selftest case holds it.
- **`docker compose run` / `docker-compose run`** into the production services backend and postgres
  is refused, like compose exec. That covers TheHub's thehub-backend and thehub-postgres and
  MyKronos's mykronos-backend, which is also service `backend`. MyKronos has no postgres service: its
  compose file lists backend and frontend only, which answers the review's question.
- **The compose message** now says "docker compose exec/run" and names the services. The docker exec
  message is unchanged.
- **An uncapped `docker run` of a test runner** (pytest, `python -m pytest`, tox, nox) is refused
  unless the same invocation carries both `--cpus` and `--memory`/`-m <n>`. `python -m pytest` is
  not read as a memory cap. Compose invocations are left to the compose rule.
- docs/11-ai-agent-controls.md: the row covers compose run, the docker run caps and the service names.

## Verified independently

- **Red first:** 14 new selftest cases against main bd2ef2f gave 337 passed and 7 failed. The three
  eaten-endpoint commits were ALLOWED (`.../contents/bin/gh`, a quoted `.../tools/git`, a curl URL
  ending `/curl`). So were compose run of backend and postgres, an uncapped docker run of pytest, and
  one with `--cpus` only. Already blocked on main: the wrapper case and gh.exe by path. The must-allow
  cases passed.
- **Green after:** selftest 344 passed / 0 failed. Bypass corpus 224 entries, 804 runs, 0 failed.
  Pinned gitleaks: no leaks. shellcheck v0.10.0 `-S warning`: clean.
- **hook-fail-closed's 5 s timing budget failed locally**, on two no-jq cases at 5.4-5.5 s. That is
  not this change: main bd2ef2f and #184's own head 9dcbdfc take the same 5.2-5.4 s here, alternated
  run for run. This laptop's CPU is clamped at 400 MHz by firmware (max 4.2 GHz; the USB-C charger
  reports 0 V / 0 A). When #184 was built it ran the same case in 0.65 s. CI's run is the one to
  trust.

## Not verified

- Git Bash on Windows was not run.
- Not caught: compose run of a dev service with no limits (a non-production service is out of scope),
  and a capped docker run whose caps are larger than the route's. The rule checks that a cap is
  present, not its size.

## Residual risk accepted

As above.
