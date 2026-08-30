# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

`my-first-lab` is a minimal learning/test repository, not an application. It currently contains:

- `hello.py` — a single-line script (`print("Hello from Codespaces")`). Run it with `python3 hello.py`.
- `index.html` — currently empty.
- `README.md` — states this is a test repo for learning Git/GitHub.

There is no package manager config, build tooling, linter, test framework, or dependency manifest in this repository. Do not assume the presence of npm/pip/etc. tooling — check for a manifest file (e.g. `package.json`, `requirements.txt`) before assuming one exists, since none is present as of this writing.

## Working in this repo

Since this is an early-stage/learning repo, prefer small, direct changes over introducing new frameworks, build systems, or scaffolding unless the user explicitly asks for it. If the user asks to add a new capability (e.g. a web app, a test suite), treat it as greenfield work and confirm the intended stack/structure before setting one up.
