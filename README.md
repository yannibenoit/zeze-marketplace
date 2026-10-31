# apm-skills

A plugin marketplace of personal and curated agent skills, for Claude Code, GitHub Copilot CLI and [APM](https://github.com/microsoft/apm). Each plugin holds one skill, so you install only what you want.

| Plugin | Source | Use when |
|---|---|---|
| `caveman` | this repo | You want ultra-terse, low-token replies |
| `grill-me` | this repo | You want a plan or design stress-tested by questioning |
| `handoff` | this repo | You want to compact a session into a handoff doc for another agent |
| `prd` | this repo | You want a Product Requirements Document for a feature |
| `write-a-skill` | this repo | You want to author a new agent skill |
| `andrej-karpathy-skills` | [multica-ai/andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | Writing, reviewing or refactoring code |
| `visual-pr` | [humanlayer/skills](https://github.com/humanlayer/skills/tree/main/plugins/visual-pr) | Invoked by name: create/update a PR with a visual outline |
| `show-me` | [humanlayer/skills](https://github.com/humanlayer/skills/tree/main/plugins/show-me) | Invoked by name: explain the current topic visually |
| `grilling` | [mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/productivity/grilling) | Stress-test a plan or decision through structured question rounds |
| `caveman-julius` | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman/tree/main/skills/caveman) | Terse answers that preserve technical details |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail/tree/main/skills) | Six skills: ponytail, review, audit, debt, gain and help |
| `dbt` | [dbt-labs/dbt-agent-skills](https://github.com/dbt-labs/dbt-agent-skills/tree/main/skills/dbt) | Twelve dbt skills: models, unit tests, semantic layer, docs, MCP server, job errors |

Third-party plugins are pinned to reviewed commits (`ref:` in `apm.yml`).

## Install

Replace `<owner>/<repo>` with the GitHub repo holding this marketplace (or a local path to a checkout).

Claude Code:

```sh
/plugin install caveman --marketplace <owner>/<repo>
# or
/plugin marketplace add <owner>/<repo>
/plugin install caveman@apm-skills
```

GitHub Copilot CLI:

```sh
copilot plugin marketplace add <owner>/<repo>
copilot plugin install caveman@apm-skills
```

APM (per project, recorded in `apm.yml`):

```sh
apm marketplace add <owner>/<repo>
apm install caveman@apm-skills
```

## Layout

```
apm.yml                               # source of truth: marketplace: block
.claude-plugin/marketplace.json       # generated for Claude Code
.github/plugin/marketplace.json       # generated for Copilot CLI
plugins/<name>/.claude-plugin/plugin.json
plugins/<name>/skills/<name>/SKILL.md
```

## Maintain

- **Add your own skill:** create `plugins/<name>/skills/<name>/SKILL.md` (frontmatter `name` must match the folder) and `plugins/<name>/.claude-plugin/plugin.json`, then add an entry under `marketplace.packages` in `apm.yml`.
- **Add a third-party plugin:** add an entry with `source: <owner>/<repo>`, optional `subdir:`, and `ref: <commit sha>` after reviewing its content.
- **Refresh remote pins:** run `scripts/update-remote-skills.sh` to point each remote GitHub package at its repository's current default-branch HEAD, increment the top-level `apm.yml` patch version once if any pins change, and rebuild both catalogs. Local `./plugins/...` packages are explicitly skipped. Use `--dry-run` to preview; it does not change the version.
- **Add a remote skill:** run `scripts/add-remote-skill.sh <repository-url>` with an HTTPS GitHub or GitLab repository URL, or link directly to a skill's `SKILL.md`. The script guesses the package name and description; use `--name` or `--description` to override them. The GitHub `owner/repo` shorthand also works. The package is pinned to the current default-branch HEAD, the top-level patch version is incremented, and both catalogs are rebuilt. Use `--dry-run` to preview without changing files.
- **Rebuild:** run `apm pack` and commit both generated `marketplace.json` files. Never edit them by hand.
- Remote updates advance the pin without reviewing the upstream diff; inspect changes before installing or publishing updated skills.
