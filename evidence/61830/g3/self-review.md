# Self-review — TheHub #61830 (keel: every step runs on a linux-tagged worker)

Mode: solo (POAM-008); agent self-review per the operator's 2026-11-04 decision
PR: #180   Author: Claude Opus 5.5 on the Linux runner laptop (AI-authored)   Date: 2026-11-16
verdict: pass

## Verified independently

- **The cause:** the pipeline had no tags, so every check, get and task could land only on the
  Windows host's untagged worker; on 2026-11-16 it held 120 containers with 32 builds queued while
  linux-1..3 held 0 (relayed by the PO from Concourse).
- **Nothing needs that host:** a grep of ci/pipeline.yml, ci/tasks, ci/scripts and
  ci/vars.example.yml finds no host.docker.internal, 192.168.x, 127.0.0.1:5000, localhost service
  or Vault address. MyKronos is `https://mykronos.toddbenson.net`; every image is pulled from a
  public registry.
- **Coverage, counted from the parsed YAML:** every resource, every get/put and every task, hooks
  and the `mykronos_preflight` anchor included, carries `tags: [linux]`.
- **test/worker-tags.test.py** (lint): 110 untagged steps on main, 0 here; it also shows itself
  failing on an untagged task and an untagged resource.
- Tag lines on get/put steps go at the end of each step, so `get: daily-0600` keeps
  `trigger: true` directly under it (poam-wiring.test.py reads that).
- Full suite (python:3.13, --cpus 2 --memory 2g): every manifest test passes; selftest, corpus,
  evals and validate-pipeline pass.

## Agent findings

None. No three-pass agent review was run.

## Not verified

- **That the Linux workers run every lane:** CodeQL (2 GB), grype and checkov have not run on
  linux-1/linux-2 yet. Each worker is capped at 5 GB / 4 CPUs; unverified until a full chain runs.
- **That set_pipeline itself needs no worker tag:** it runs on the web node; the artifact it reads
  comes from the (now tagged) get. Unverified on this Concourse.
- **The ~5m20s ceiling** the set-pipeline gets hit is not explained by any timeout in the pipeline;
  probably a platform default on an overloaded worker. Unverified.

## Cold-read notes

- A deployment with no `linux`-tagged worker now runs nothing: every step waits. That is the
  intended trade, and README says so; a fork changes or removes the tag in one pass.
- Images are pulled by tag from Docker Hub on the Linux workers' own network.

## Residual risk accepted

None.
