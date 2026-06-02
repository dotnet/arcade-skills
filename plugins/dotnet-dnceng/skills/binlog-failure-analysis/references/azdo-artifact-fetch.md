# AzDO artifact fetch — full recipe

Companion reference for `binlog-failure-analysis`. Covers all the edge cases the SKILL.md hand-waves: discovering the build id from a check-run event, authenticating against `dnceng/internal` or `devdiv/DevDiv`, fallback when `PostBuildLogs_*` is absent, and disambiguating multiple binlogs in one artifact.

**Required CLI tools:** `gh` (GitHub CLI), `jq` (JSON parsing), `curl` (HTTP), `unzip` (artifact extraction). All snippets in this file assume the four are on `PATH`.

## 1. Find the failing AzDO build for a PR

If the caller already knows the build id, skip this section.

### From a `check_run` event payload

GitHub's check-run event sets:

```jsonc
{
  "action": "completed",
  "check_run": {
    "app": { "slug": "azure-pipelines" },
    "conclusion": "failure",
    "external_id": "1435255",                            // <-- the AzDO build id
    "details_url": "https://dev.azure.com/.../?buildId=1435255",
    "head_sha":    "<sha>",
    "pull_requests": [ { "number": 13835 } ]
  }
}
```

Prefer `external_id` (set by Azure Pipelines). Fall back to parsing `buildId=N` from `details_url`. Gate on `app.slug == 'azure-pipelines'` (or whatever slug the repo's AzDO check uses — verify once per repo).

### From a PR number (slash command)

```bash
# Get the head SHA, then the latest failed azure-pipelines check on that SHA.
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')

CHECK=$(gh api "repos/$GITHUB_REPOSITORY/commits/$HEAD_SHA/check-runs?per_page=100" \
  --jq '[.check_runs[] | select(.app.slug == "azure-pipelines" and .conclusion == "failure")]
        | sort_by(.completed_at) | reverse | .[0]')

BUILD_ID=$(echo "$CHECK" | jq -r '.external_id // (.details_url | capture("buildId=(?<id>[0-9]+)") | .id)')
```

## 2. Authenticate (only for internal projects)

| Project                 | Read access     | How to authenticate |
|-------------------------|-----------------|---------------------|
| `dnceng-public/public`  | Anonymous       | No token. Omit the `Authorization` header. |
| `devdiv/DevDiv`         | Federated AAD   | `azure/login@v2` with `client-id`, `tenant-id`, `allow-no-subscriptions: true`, then `az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798`. |
| `dnceng/internal`       | Federated AAD   | Same pattern; `azureauth ado token --organization https://dev.azure.com/dnceng/` also works for local/dev runs. |

The AzDO resource GUID `499b84ac-1321-427f-aa17-267ca6975798` is constant across all orgs.

For local development against an internal project:

```bash
TOKEN=$(az account get-access-token \
  --resource 499b84ac-1321-427f-aa17-267ca6975798 \
  --query accessToken -o tsv)
export AZDO_TOKEN="$TOKEN"
```

## 3. List artifacts and download

```bash
ARTIFACTS=$(curl -fsSL \
  ${AZDO_TOKEN:+ -H "Authorization: Bearer $AZDO_TOKEN"} \
  "https://dev.azure.com/$AZDO_ORG/$AZDO_PROJECT/_apis/build/builds/$AZDO_BUILD_ID/artifacts?api-version=7.1")
```

The response shape:

```json
{
  "value": [
    {
      "name": "PostBuildLogs_Build_Linux_Debug_Attempt1",
      "resource": {
        "type": "Container",
        "downloadUrl": "https://dev.azure.com/.../_apis/resources/Containers/.../zip"
      }
    }
  ]
}
```

### Artifact naming conventions

| Pipeline kind           | Artifact name pattern                                  |
|-------------------------|--------------------------------------------------------|
| arcade-onboarded (any)  | `PostBuildLogs_<StageLabel>_<JobLabel>_Attempt<N>`     |
| dnceng-public/runtime   | `Logs_Build_Attempt<N>_<leg>` (per-leg, not stage)     |
| Custom / non-arcade     | Anything — fall back to globbing `*.binlog` post-unzip |

Prefer `PostBuildLogs_*` first; fall back to `Logs_*`; final fallback is "any artifact that contains a `*.binlog` on extraction". The `eng/common/core-templates/steps/publish-logs.yml` template in arcade is the source of truth for the `PostBuildLogs_*` convention.

### Download

Use the AzDO artifacts endpoint with `artifactName` + `$format=zip` to download the artifact as a zip — this is the canonical pattern used elsewhere in this repo (see `plugins/dotnet-dnceng/skills/ci-analysis/references/helix-artifacts.md`). The `downloadUrl` returned in the artifacts list is also usable when the underlying storage type is `Container` (it points at a pre-formatted zip stream), but the endpoint form is portable across both `Container` and modern `PipelineArtifact` storage:

```bash
ZIP_URL="https://dev.azure.com/$AZDO_ORG/$AZDO_PROJECT/_apis/build/builds/$AZDO_BUILD_ID/artifacts?artifactName=$ARTIFACT_NAME&api-version=7.1&\$format=zip"
curl -fsSL ${AZDO_TOKEN:+ -H "Authorization: Bearer $AZDO_TOKEN"} -o /tmp/logs.zip "$ZIP_URL"
unzip -q -o /tmp/logs.zip -d /tmp/azdo-binlog
```

## 4. Pick the right `*.binlog`

A `PostBuildLogs_*` artifact typically contains multiple binlogs. The internal layout mirrors arcade's `artifacts/log/<config>/`:

```text
PostBuildLogs/Build/Linux_Debug/
  Build.binlog
  Restore.binlog
  TrimmingTests.binlog
  ...
```

Heuristics, in order of preference:

1. **Most-recently-modified `*.binlog`** — the failing leg's binlog is typically newest. Works for ~95% of real failures.

   ```bash
   BINLOG=$(find /tmp/azdo-binlog -name '*.binlog' -type f \
            -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
   ```

2. **Largest binlog** — when the build has a clear "main" compile leg, that binlog is usually the largest. Useful for runtime/sdk builds.

3. **`Build.binlog`** — most arcade-onboarded repos publish a canonical `Build.binlog` at the root of the `PostBuildLogs/<Stage>/<Job>/` directory.

If none of those produce an MSBuild-failed binlog (i.e., the build-overview tool reports SUCCEEDED), the failure was downstream of MSBuild (tests, Helix, signing). Report that and stop.

## 5. Common failure modes

| Symptom                             | Likely cause | Fix |
|-------------------------------------|--------------|-----|
| `404 Not Found` on artifacts list   | Build id wrong, or build was deleted by retention | Verify with `curl ...builds/$AZDO_BUILD_ID?api-version=7.1`. |
| `401 Unauthorized`                  | Anonymous request against internal project       | Wire `azure/login@v2` and pass `AZDO_TOKEN`. |
| `403 Forbidden` after login         | Federated identity has wrong subject pattern     | Subject must match `repo:<owner>/<repo>:ref:refs/heads/<branch>`. |
| Artifact zip extracts to no `*.binlog` | Pipeline didn't publish binlogs              | Cannot help — pipeline must be updated to use arcade's `publish-logs.yml`. |
| `TF400813: The user is not authorized` | Federated identity has no AzDO project access | Add the federated identity as a project member with **Reader** + **Build (Read)**. |

## 6. Cheap sanity check before kicking off the analyst

```bash
# Returns SUCCEEDED / FAILED / PARTIALLYSUCCEEDED.
BUILD_RESULT=$(curl -fsSL \
  ${AZDO_TOKEN:+ -H "Authorization: Bearer $AZDO_TOKEN"} \
  "https://dev.azure.com/$AZDO_ORG/$AZDO_PROJECT/_apis/build/builds/$AZDO_BUILD_ID?api-version=7.1" \
  | jq -r '.result // .status' | tr '[:lower:]' '[:upper:]')

if [ "$BUILD_RESULT" != "FAILED" ] && [ "$BUILD_RESULT" != "PARTIALLYSUCCEEDED" ]; then
  echo "Build $AZDO_BUILD_ID is $BUILD_RESULT — nothing to analyse"; exit 0
fi
```

Saves a full artifact download for builds that aren't actually failed (e.g., a stale `check_run` event arrives after a retry succeeds).
