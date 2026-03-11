# Contributing

Thanks for your interest in contributing. We expect to accept external contributions, but the bar for merging is intentionally high.

This repository contains shared building blocks for coding agents used in .NET product repos:

- Skills: reusable, task focused instruction packs
- Agents: role based configurations that bundle tool expectations and skill selection

Because these artifacts can affect many users and workflows, we prioritize correctness, clarity, and long term maintainability over speed.

## Code ownership

Every plugin, skill, and agent must have designated owners in the `.github/CODEOWNERS` file. When you add a new skill or agent, add a matching CODEOWNERS entry. Ownership must be either:

- **Two or more FTE GitHub aliases** (e.g., `@user1 @user2`), or
- **A GitHub team alias** (e.g., `@dotnet/my-team`)

This ensures that every contribution area has accountable reviewers and that PRs are automatically routed to the right people.

## Repository layout

```text
plugins/
  <plugin>/
    plugin.json
    skills/
      <skill-name>/
        SKILL.md
        scripts/
        references/
        assets/
    agents/
      <agent-name>.agent.md
tests/
  <plugin>/
    <skill-name>/
      eval.yaml
      <fixture files>
```

Every plugin must have a `plugin.json` file in the plugin root that is linked to from the `marketplace.json` file.

### Plugin organization

Skills are grouped into domain-specific plugins. When proposing a new skill, place it in the plugin that best matches its domain.

To create a new plugin:

1. Add `plugins/<plugin-name>/plugin.json` and a `skills/` directory beneath it.
2. Add a matching entry in both `.github/plugin/marketplace.json` and `.claude-plugin/marketplace.json`. The `.claude-plugin/marketplace.json` file must remain an exact copy of `.github/plugin/marketplace.json`, so any change to one file must be applied to the other in the same way.
3. Add a CODEOWNERS entry for the new plugin and its tests (see [Code ownership](#code-ownership)).
4. Add the plugin to the **What's Included** table in the root `README.md`.
5. Create a `tests/<plugin-name>/` directory for skill tests.

See existing plugins for the expected format.

## Before you start

- Search existing issues and pull requests to avoid duplicates.
- Start with an issue before you submit a pull request for a new skill, a new agent, or any non trivial change. This helps us align on scope and avoids wasted work.
- Small fixes like typos, broken links, or clearly isolated corrections can go straight to a pull request.
- Keep changes small and focused. One skill or one agent per pull request is a good default.

## What we look for

We are most likely to accept contributions that are:

- Narrow in scope and easy to review
- Clearly motivated by a real use case
- Tool conscious and explicit about assumptions
- Verifiable with concrete validation steps
- Written to be durable across repo changes

We are less likely to accept contributions that:

- Add broad frameworks, meta tooling, or large reorganizations
- Duplicate guidance that already exists in another skill
- Encode private environment details, credentials, or company specific secrets
- Depend on proprietary tools or access that most contributors will not have

## Proposing a new skill

A skill should be self-contained and:

- Clearly state **what it does** and **when to use it**.
- Specify required inputs (repo context, environment, access needs).
- Prefer concrete checklists and verification steps over vague guidance.

Create a new folder under a plugin's `skills/` directory:

```text
plugins/<plugin>/skills/<skill-name>/SKILL.md
```

A skill should answer three questions up front:

1. What outcome does the skill produce
2. When should an agent use it
3. How does the agent validate success

### Skill naming

Use short, kebab-case names that mirror how developers naturally phrase the task, prioritizing keyword overlap over grammar — e.g., `add-aspnet-auth`, `configure-jwt-auth`, `setup-identity-server`. Gerund style (`verb-ing`) is also acceptable.

The `SKILL.md` is required to have front-matter at a minimum:

```yaml
---
name: <skill-name>
description: <description of what the skill does, when to use it, and when not to use it>
---
```

> **Tip:** The `description` field is used by the agent runtime to decide whether to load the full skill.
> Include **when to use** and **when not to use** guidance directly in the description so the agent can
> select or skip skills without reading the entire `SKILL.md`.

### Recommended `SKILL.md` sections

- **Purpose**: one paragraph describing the outcome.
- **When to use** / **When not to use** (put the essentials in the frontmatter `description`).
- **Inputs**: what the agent needs (files, commands, permissions).
- **Workflow**: numbered steps with checkpoints.
- **Validation**: how to confirm the result (tests, linters, manual checks).
- **Common pitfalls**: known traps and how to avoid them.

### Skill naming rules ([agentskills.io spec](https://agentskills.io/specification))

- 1–64 characters
- Lowercase alphanumeric and hyphens only
- No consecutive hyphens, no leading/trailing hyphens
- Must match the directory name

### Skill description rules

- 1–1024 characters
- Required in YAML frontmatter

## Proposing a new agent

An agent definition should be opinionated but bounded:

- Describe the **role** (e.g., "Build Expert", "Security Reviewer").
- Define boundaries (what the agent should not do).
- List the skills it expects to use and how it chooses among them.

Add an agent file under a plugin's `agents/` directory:

```text
plugins/<plugin>/agents/<agent-name>.agent.md
```

## Testing and validation

### Checkin validation

Pull requests are validated automatically by two workflows:

1. **CODEOWNERS validation** — every skill and test folder must have a CODEOWNERS entry with 2+ individuals or 1+ team.
2. **Structural validation** — checks plugin.json, SKILL.md frontmatter, eval.yaml schema, marketplace.json consistency, and directory structure conventions.

### Writing skill tests

Each skill should have an `eval.yaml` file that defines test scenarios:

```text
tests/<plugin>/<skill-name>/eval.yaml
```

A minimal eval file:

```yaml
scenarios:
  - name: "Describe what the agent should do"
    prompt: "The prompt sent to the agent"
    assertions:
      - type: "output_contains"
        value: "expected text in agent output"
    timeout: 120
```

#### Test fixture files

If a scenario requires files in the agent's working directory, place them alongside `eval.yaml` and use `copy_test_files: true`:

```yaml
scenarios:
  - name: "Diagnose build failure"
    prompt: "Why does this project fail to build?"
    setup:
      copy_test_files: true
    assertions:
      - type: "output_matches"
        pattern: "CS\\d{4}"
```

#### Assertion types

| Type | Description |
|------|-------------|
| `output_contains` | Agent output contains `value` (case-insensitive) |
| `output_not_contains` | Agent output does NOT contain `value` |
| `output_matches` | Agent output matches `pattern` (regex) |
| `output_not_matches` | Agent output does NOT match `pattern` |
| `file_exists` | File matching `path` glob exists in work dir |
| `file_not_exists` | No file matching `path` glob exists in work dir |
| `file_contains` | File matching `path` glob contains `value` |
| `exit_success` | Agent produced non-empty output |

#### Scenario constraints

```yaml
scenarios:
  - name: "Test scenario"
    prompt: "Do the thing"
    expect_tools: ["bash"]
    reject_tools: ["create_file"]
    max_turns: 10
```

## Writing style

- Be concise and specific.
- Prefer numbered steps for workflows.
- Prefer checklists for requirements.
- Avoid excessive formatting and avoid clever wording that could be misread by an agent.

## Security and safety

- Do not include secrets, tokens, or internal URLs.
- If you discover a security issue, do not open a public issue. Use the repository or organization security reporting process instead.

## Licensing and provenance

Only submit content that you have the right to contribute.

- Do not include copyrighted text from other projects.
- You may be asked to confirm that your contribution is original or appropriately licensed.
