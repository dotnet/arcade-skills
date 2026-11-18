# Shared Copilot PAT Pool

`shared_pat_pool.md` selects a random Copilot PAT from a numbered pool of secrets. This addresses limitations that arise from having a single PAT shared across all agentic workflows, such as rate-limiting.

This is the single maintained copy for dotnet repositories. Repositories import it remotely instead of copying it, so there are no drifting copies and no three-way merges.

**This is a stop-gap workaround.** As soon as organization/enterprise billing is available to the dotnet org, this approach will be removed from our workflows.

## How consumption works

1. A consuming workflow lists this file under `imports:` in its frontmatter (see [Usage](#usage)).
2. `gh aw compile` fetches the file from `dotnet/arcade-skills` at the requested ref, caches it under `.github/aw/imports/`, and inlines the `pat_pool` job into the consumer's `.lock.yml`.
3. At run time, GitHub Actions executes only the consumer's committed `.lock.yml`. Nothing is fetched from `dotnet/arcade-skills`. The consumer's `copilot-pat-pool` environment still decides which branches can read the PAT secrets.
4. A change merged here reaches a consumer the next time that consumer recompiles and merges the regenerated lock files.

### Why `@main`

Consumers import from `@main` so that updating the shared flow does not require release work (tags or per-repository SHA bumps). `@main` also cannot resolve to an unreviewed fork commit, unlike an arbitrary SHA. The trade-off is that any recompile picks up the current `main` content; commit `.github/aw/imports/` so reviewers see the shared-file diff in the consumer's pull request.

We can move to SHA pinning once the behavior stabilizes. A pinned SHA must be verified to be an ancestor of `dotnet/arcade-skills` `main`; GitHub serves fork commits through the parent repository's path, so a SHA alone does not prove the content was reviewed here.

### Compatibility contract

Consumers reference the job and its output by name. Keep these stable:

- Job name: `pat_pool`
- Output: `pat_number` (`0`-`9`, or empty when the pool is empty)
- Inputs: `environment`, `COPILOT_PAT_0`..`COPILOT_PAT_9`, `random_seed`

Changes here must compile with the oldest `gh aw` version used by consumers (currently **v1.2.2**).

## Repository Onboarding

To use Agentic Workflows with the shared PAT pool in a dotnet org repository:

1. Follow the instructions for [Configuring Your Repository | Agentic Authoring | GitHub Agentic Workflows][configure-repo]. Use `gh aw` **v1.2.2 or newer**.
2. Create the environment and PAT secrets described below.
3. Import `shared_pat_pool.md` in each agentic workflow (see [Usage](#usage)) and add the [validation workflow](#validating-the-pool).
4. Compile with `gh aw compile --schedule-seed <org>/<repo>` and commit the workflow sources, `.lock.yml` files, and `.github/aw/imports/`.

**Install or upgrade the `gh aw` CLI and check the version**

```sh
gh extension install github/gh-aw --force
gh aw --version
```

### Environment

Create an environment for the agentic workflows:
  - _Configuring these settings requires repo admin permission_
  - https://github.com/dotnet/{repo}/settings/environments
  - Recommended Name: **copilot-pat-pool**
  - Recommended Deployment branches and tags: **Protected branches only**

This environment is used for all agentic workflows, restricting agentic workflows to the repo's protected branches and preventing the workflows from accessing secrets defined for other environments.

## PAT Management

Team members provide PATs into the pool with secret names matching the pattern of `{pool-name}_{0-9}`, such as `COPILOT_PAT_0`.

[Use this link to prefill the PAT creation form with the required settings][create-pat]:

1. **Resource owner** is your **user account**, not an organization.
2. **Copilot Requests (Read)** must be the only permission granted.
3. **8-day expiration** must be used, which enforces a weekly renewal.
4. **Repository access** set to **Public repositories** only.

The **Token Name** _does not_ need to match the secret name and is only visible to the owner of the PAT. It's recommended to use a token name indicating the PAT is used for dotnet org agentic workflows. The **Description** is also only used for your own reference.

Team members providing PATs for workflows should set weekly recurring reminders to regenerate and update their PATs in the PAT pool. With an 8-day expiration, renewal can be done on the same day each week.

## PAT Pool Secrets

PATs are added to repositories as **Environment Secrets** for the environment created above. _This requires repo admin permission_.

* **Settings** >
   * **Environments** >
      * **copilot-pat-pool** (or other environment name) >
         * **Add environment secret** (or edit your existing secret)
            * Enter your secret name of `COPILOT_PAT_{0-9}` and paste in your PAT

This can also be accomplished using the `gh` CLI, specifying the repo and environment arguments.

```sh
# Register the PAT secret. This will prompt for you to paste the PAT.
gh secret set "<pool_name>_<0-9>" --repo <org>/<repo> --env "copilot-pat-pool"
```

It's also helpful to record who owns each PAT within the pool. To capture which team member is associated with each PAT, a `<pool_name>_<0-9>_<username>` "sidecar secret" can be added alongside the PAT secret to make the username for the PAT pool entry visible. This sidecar secret must have a non-empty value, but it's never consumed, so any value is sufficient.

```sh
# Record a sidecar secret that presents who owns this PAT.
gh secret set "<pool_name>_<0-9>_<username>" --body "<username>" --repo <org>/<repo> --env "copilot-pat-pool"
```

## Workflow Output Attribution

Team members' PATs are _only_ used for the Copilot requests from within the agentic portion of the workflow. All outputs from the workflow use the `github-actions[bot]` account token. Issues, PRs, comments, and all other content generated by the workflow will be attributed to `github-actions[bot]`--not the team member's account or token.

## Usage

The `shared_pat_pool.md` workflow import defines a custom `pat_pool` job with a `pat_number` output. Consuming workflows need two additions to their frontmatter to import this job and use the PAT number to override the `COPILOT_GITHUB_TOKEN` passed to the workflow's agent job.

```yml
# ###############################################################
# Select a PAT from the shared pool and override COPILOT_GITHUB_TOKEN.
# Run agentic jobs in an isolated `copilot-pat-pool` environment.
#
# When org-level billing is available, this will be removed.
# See https://github.com/dotnet/arcade-skills/blob/main/agentic-workflows/shared/shared_pat_pool.README.md
# ###############################################################
imports:
  - uses: dotnet/arcade-skills/agentic-workflows/shared/shared_pat_pool.md@main
    with:
      environment: copilot-pat-pool

environment: copilot-pat-pool

engine:
  id: copilot
  env:
    COPILOT_GITHUB_TOKEN: |
      ${{ case(
        needs.pat_pool.outputs.pat_number == '0', secrets.COPILOT_PAT_0,
        needs.pat_pool.outputs.pat_number == '1', secrets.COPILOT_PAT_1,
        needs.pat_pool.outputs.pat_number == '2', secrets.COPILOT_PAT_2,
        needs.pat_pool.outputs.pat_number == '3', secrets.COPILOT_PAT_3,
        needs.pat_pool.outputs.pat_number == '4', secrets.COPILOT_PAT_4,
        needs.pat_pool.outputs.pat_number == '5', secrets.COPILOT_PAT_5,
        needs.pat_pool.outputs.pat_number == '6', secrets.COPILOT_PAT_6,
        needs.pat_pool.outputs.pat_number == '7', secrets.COPILOT_PAT_7,
        needs.pat_pool.outputs.pat_number == '8', secrets.COPILOT_PAT_8,
        needs.pat_pool.outputs.pat_number == '9', secrets.COPILOT_PAT_9,
        'NO COPILOT PAT AVAILABLE')
      }}
```

The `COPILOT_GITHUB_TOKEN` expression can be collapsed onto a single line if desired. `gh-aw compile` automatically wires `pat_pool` into the activation and agent jobs' `needs:` graph because of the `needs.pat_pool.` references within the `engine.env` property.

```sh
gh aw compile <workflow-name> --schedule-seed <org>/<repo>
```

Do not import both this file and a repository-local `pat_pool.md` into the same workflow; both define the `pat_pool` job.

### Migrating from a local copy

Replace `uses: shared/pat_pool.md` with the remote path above in each workflow, delete the local `shared/pat_pool.md`, recompile every workflow, and commit the regenerated lock files and `.github/aw/imports/`. The job name, output, and `case` expression do not change.

### Specifying the environment

The `environment` must be specified both to the `shared_pat_pool.md` import and to the containing workflow to ensure both jobs access the PAT pool from the same environment. The `copilot-pat-pool` environment name is recommended as the isolated environment for agentic workflows that use the PAT pool.

### Customizing the pool

The import declares 10 optional inputs (`COPILOT_PAT_0` through `COPILOT_PAT_9`), each defaulting to `secrets.COPILOT_PAT_#` of the matching number. To point a workflow at a different pool of repository secrets, use the parameterized `uses`/`with` form when importing and pass the substitute secrets as the `COPILOT_PAT_#` inputs:

```yml
imports:
  - uses: dotnet/arcade-skills/agentic-workflows/shared/shared_pat_pool.md@main
    with:
      environment: copilot-pat-pool
      COPILOT_PAT_0: ${{ secrets.MY_TEAM_PAT_0 }}
      COPILOT_PAT_1: ${{ secrets.MY_TEAM_PAT_1 }}
      # Unspecified inputs default to `secrets.COPILOT_PAT_#` lookups
```

The secrets passed via `with:` must match the secrets referenced in the consuming workflow's `case` expression that overrides `COPILOT_GITHUB_TOKEN`--both sides need to agree on which secret backs each `COPILOT_PAT_#` slot. Update the `case` expression accordingly:

```yml
engine:
  id: copilot
  env:
    COPILOT_GITHUB_TOKEN: ${{ case(needs.pat_pool.outputs.pat_number == '0', secrets.MY_TEAM_PAT_0, needs.pat_pool.outputs.pat_number == '1', secrets.MY_TEAM_PAT_1, ..., 'NO COPILOT PAT AVAILABLE') }}
```

This approach aligns with GitHub's documented guidance for [passing secrets][passing-secrets] between workflows, where the `pat_pool` job returns a PAT number and the `case` statement acts as a secret store to look the PAT secret up based on the selected number.

## Validating the Pool

[`validate-pat-pool.yml`](../../.github/workflows/validate-pat-pool.yml) is a reusable workflow that makes a real Copilot request with each PAT in the pool. Call it from a scheduled workflow in the consuming repository:

```yml
name: Validate PAT Pool

on:
  schedule:
    - cron: '17 2 * * *'
  workflow_dispatch:

permissions: {}

jobs:
  validate:
    if: ${{ github.event_name == 'workflow_dispatch' || !github.event.repository.fork }}
    uses: dotnet/arcade-skills/.github/workflows/validate-pat-pool.yml@<sha> # main
    with:
      environment: copilot-pat-pool
```

Unlike the compile-time import, a reusable workflow is fetched when it runs, with access to the caller's environment secrets. Pin it to a full commit SHA that is on `dotnet/arcade-skills` `main`, and update the SHA deliberately (for example, through Dependabot's `github-actions` ecosystem). The called job declares `environment:`, so the `COPILOT_PAT_#` secrets resolve from the caller's environment and do not need to be passed with `secrets:`.

## Design / Security

There are several details of this implementation that keep our workflows and repositories safe.

1. **Secrets adhere to existing trust boundaries.** The pool of PAT secrets is
   provided to a dedicated step within the `pat_pool` job. That job runs
   after `pre_activation` and contains only the trusted checkout and action
   steps--no untrusted context or input is within scope. The
   `select-pat-number` step sends each non-empty secret only to the fixed
   `https://api.github.com/user` endpoint and includes only entries that return
   HTTP 200. GitHub CLI receives the token through `GH_TOKEN`, with a 15-second
   process timeout and response bodies suppressed. This excludes expired, revoked,
   and otherwise unauthenticated PATs before random selection. This check does
   not verify Copilot permissions or licensing; the scheduled
   [validation workflow](#validating-the-pool) exercises those separately with
   an actual Copilot request.
1. **The `pat_pool` job emits only a number, never a secret.** Its sole output,
   `pat_number`, is the 0-9 index of the selected PAT (or empty when the pool
   is empty). The actual secret materializes only later, in the activation
   job's `engine.env` mapping, where the `case()` expression resolves the
   number to the matching secret. This follows GitHub's guidance for
   [passing secrets][passing-secrets] between jobs or workflows, with the
   `case` statement acting as a very simple secret store.
1. **The `select-pat-number` step does not require any permissions.** It
   reads only the `COPILOT_PAT_#` environment variables passed to it, makes
   authentication checks against GitHub, and writes only the selected number
   to `GITHUB_OUTPUT`. The job that hosts it sets `permissions:` to the workflow
   defaults (no elevated scopes). PAT values and API response bodies are never
   written to logs, summaries, artifacts, outputs, or command arguments.
1. **The shared source is reviewed once, centrally.** Changes to this file affect
   every consumer on its next compile, so they require review from the
   CODEOWNERS of this folder. Consumers still review the regenerated lock files
   and `.github/aw/imports/` diff before merging.
1. **The implementation uses supported Agentic Workflow extensibility hooks.**
   Defining a custom job inside an [imported workflow file][imports] is
   supported by `gh aw compile`. gh-aw automatically
   wires `pat_pool` into the activation job's `needs:` graph based on the
   `needs.pat_pool.outputs.pat_number` references in `engine.env`. The
   [secret override][secret-override] capability supplies the `COPILOT_GITHUB_TOKEN`
   value via `engine.env` rather than the default secret of the same name.

## Known Issues

### Missing pre-activation job

The `pat_pool` import integration requires that the workflow's compilation results in a `pre_activation` job. If nothing in your workflow definition produces a `pre_activation` job, a compilation error will be received.

```text
✗ Failed workflows:
  ✗ <workflow-name>.md

.github\workflows\<workflow-name>.md:1:1: error: failed to generate YAML: failed to build and validate jobs: job dependency validation failed: job 'pat_pool' depends on non-existent job 'pre_activation'
```

To work around this, add `on.permissions: {}` to your workflow, which forces a no-op `pre_activation` job to be generated.

```yml
on:
  permissions: {}
```

See: [Activation 'needs' does not incorporate jobs in engine.env expressions (github/gh-aw#30790)](https://github.com/github/gh-aw/issues/30790)

## References

- [Agentic Workflows CLI Extension][cli-setup]
- [Agentic Authoring][configure-repo]
- [Authentication][authentication]
- [Agentic Workflow Imports][imports]
- [Custom Steps][steps]
- [Custom Jobs][jobs]
- [Job Outputs][job-outputs]
- [Engine Configuration][engine]
- [Engine Environment Variables][engine-vars]
- [Update agentic engine token handling to use user-provided secrets (github/gh-aw#18017)][secret-override]
- [Case Function in Workflow Expressions][case-expression]
- [Passing a secret between jobs or workflows][passing-secrets]
- [Reusing workflows][reusing-workflows]

[cli-setup]: https://github.github.com/gh-aw/setup/cli/
[configure-repo]: https://github.github.com/gh-aw/guides/agentic-authoring/#configuring-your-repository
[authentication]: https://github.github.com/gh-aw/reference/auth/
[create-pat]: https://github.com/settings/personal-access-tokens/new?name=dotnet%20org%20agentic%20workflows&description=GitHub+Agentic+Workflows+-+Copilot+engine+authentication.++Used+for+dotnet+org+workflows.+MUST+be+configured+with+only+Copilot+Requests+permissions+and+user+account+as+resource+owner.+Weekly+expiration+and+required+renewal.&user_copilot_requests=read&expires_in=8
[imports]: https://github.github.com/gh-aw/reference/imports/
[steps]: https://github.github.com/gh-aw/reference/frontmatter/#custom-steps-steps
[jobs]: https://github.github.com/gh-aw/reference/frontmatter/#custom-jobs-jobs
[job-outputs]: https://github.github.com/gh-aw/reference/frontmatter/#job-outputs
[engine]: https://github.github.com/gh-aw/reference/frontmatter/#ai-engine-engine
[engine-vars]: https://github.github.com/gh-aw/reference/engines/#engine-environment-variables
[secret-override]: https://github.com/github/gh-aw/pull/18017
[case-expression]: https://docs.github.com/actions/reference/workflows-and-actions/expressions#case
[passing-secrets]: https://docs.github.com/actions/reference/workflows-and-actions/workflow-commands#example-masking-and-passing-a-secret-between-jobs-or-workflows
[reusing-workflows]: https://docs.github.com/actions/how-tos/reuse-automations/reuse-workflows
