# .NET Arcade Skills

Reusable AI skills, plugins, and agents for use in .NET product repos such as [dotnet/runtime](https://github.com/dotnet/runtime).

This repository contains shared building blocks for coding agents:

- **Skills**: reusable, task-focused instruction packs
- **Agents**: role-based configurations that bundle tool expectations and skill selection

For information about the Agent Skills standard, see [agentskills.io](http://agentskills.io).

## What's Included

| Plugin | Description |
|--------|-------------|
| `dotnet-dnceng` | Lightweight CI entry point: `hlx` CLI investigation (`helix-cli`), known-issue history, and the `ci-investigator` agent. No MCP servers loaded by default. |
| `dotnet-helix` | Deep CI failure investigation via the Helix/Azure DevOps MCP server: build/test triage, Helix logs, pipeline and crash-dump analysis. |
| `dotnet-binlog` | Analyze failed MSBuild binary logs from Azure DevOps builds via the binlog MCP server, without rebuilding locally. |
| `dotnet-codeflow` | Dependency flow across .NET repos: Maestro/BAR subscriptions, VMR codeflow health, and cross-repo dependency tracing. |
| `dotnet-arcade` | Build and validate the .NET Arcade SDK locally against consuming repositories. |
| `dotnet-compliance` | Compliance and security: BinSkim binary scanning and SDL finding analysis. |
| *(more coming soon)* | Contribute one! See [CONTRIBUTING.md](CONTRIBUTING.md). |

## Installation

### Copilot CLI / Claude Code

1. Launch Copilot CLI or Claude Code
2. Add the marketplace:
   ```
   /plugin marketplace add dotnet/arcade-skills
   ```
3. Install a plugin:
   ```
   /plugin install <plugin>@dotnet-arcade-skills
   ```
4. Restart to load the new plugins
5. View available skills:
   ```
   /skills
   ```

### VS Code / VS Code Insiders (Preview)

```jsonc
// settings.json
{
  "chat.plugins.enabled": true,
  "chat.plugins.marketplaces": ["dotnet/arcade-skills"]
}
```

Once configured, type `/plugins` in Copilot Chat to browse and install plugins from the marketplace.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines and how to add a new plugin.

## License

See [LICENSE](LICENSE) for details.
