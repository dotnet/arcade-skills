# Repository Instructions

This repository contains skill plugins under `plugins/`. Each subdirectory in `plugins/` is an independent plugin (e.g., `plugins/arcade-build`).

## Structure

```text
plugins/
  <plugin>/
    plugin.json
    skills/
      <skill-name>/
        SKILL.md
        scripts/
        references/
    agents/
      <agent-name>.agent.md
tests/
  <plugin>/
    <skill-name>/
      eval.yaml
      <fixture files>
```

## Validation

Pull requests are validated automatically:

- **CODEOWNERS**: every skill and test folder must have designated owners
- **Structure**: plugin.json, SKILL.md frontmatter, eval.yaml schema, and marketplace consistency are checked
