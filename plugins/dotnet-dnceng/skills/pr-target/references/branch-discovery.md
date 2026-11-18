# Branch Discovery and Links

Use the caller's repository and authenticated access. There is no hardcoded
internal organization, project, repository, or credential in this skill.

## Change context and repository identity

1. Read remotes and repository instructions. Inspect changed paths before reading
   a scoped diff. Include staged and relevant untracked files without changing them.
2. Resolve a supplied PR in its actual repository, not the current fork:

   ```text
   gh pr view <number-or-url> --repo <owner/repo> --json title,body,files,labels,baseRefName,headRefName
   gh repo view <owner/repo> --json nameWithOwner,parent,defaultBranchRef,url
   ```

3. Use `upstream`, repository parent metadata, or source mappings to distinguish
   canonical component/VMR repositories from forks. Do not assume every repo
   named `runtime` belongs to the .NET organization.
4. Classify runtime/shared versus SDK/band-specific changes from the VMR's build
   configuration and source mappings where available. Do not classify all
   changes in the SDK distribution as SDK-source fixes.

## Public refs

List a bounded release family, then verify exact candidate refs:

```text
git ls-remote --heads <public-remote> "refs/heads/release/<train>*"
git ls-remote --exit-code --heads <public-remote> "refs/heads/<candidate>"
```

For GitHub, the branches and contents APIs can provide the ref SHA and version
files without fetching a checkout. Percent-encode a branch name passed as one
API path segment. A public component may use `release/10.0` where the VMR uses
`release/10.0.1xx`; verify mappings rather than replacing strings.

With `ls-remote --exit-code`, exit 2 means no matching ref; authentication,
transport, or other failures are not absence. Ensure list queries are complete
for the relevant prefix, or paginate APIs; a truncated list proves nothing.

## Internal refs and window identity

Discover the authorized internal VMR remote from local configuration or ask
for its URL/access. Use the organization's authenticated git or Azure DevOps
tools to list/read it. Never send internal ref names, private PR bodies, or
security change contents to GitHub or another public endpoint.

For 10.0+ servicing, internal General Servicing, Release Specific, and parking
destinations are VMR branches. A component's internal validation branch can
validate a change but does not replace that final VMR destination.

For each affected band:

1. List the relevant Release Specific refs, including their observed SHAs,
   separately from General Servicing, validation, and OOB refs. A complete
   inventory can establish that a specific release branch has or has not been
   cut; an unrelated Release Specific ref does not represent every release.
2. Read branding from both General Servicing and candidate Release Specific refs
   at their observed SHAs. In the VMR, start with `eng/Versions.props`.
   `VersionMajor`, `VersionMinor`, `VersionSDKMinor`, `VersionSDKMinorPatch`,
   `VersionFeature`, and `VersionPrefix` describe the SDK branding; evaluate
   property expressions rather than treating an unevaluated expression as a
   version. If the required commit is available locally, for example:

   ```text
   git show <observed-sha>:eng/Versions.props
   ```

   Otherwise use the host's authenticated contents API at that SHA. Query
   internal refs only through authorized internal tools. Component product
   branding may be elsewhere; for runtime source present in a VMR branch,
   `src/runtime/eng/Versions.props` contains its `ProductVersion`.
3. Compare like-for-like branding with the approved release. If the approval
   names the release and verified branding and refs settle the route, no
   separate QB mapping is needed. If it names only a calendar window, use an
   authoritative release schedule or mapping; ask the QB only if the
   relationship remains unresolved. Explain that the mapping decides whether
   the release matches Release Specific or General Servicing, or is later and
   must wait to merge; do not claim every mapping yields a different branch.

Take transition state and conflicting evidence into account:

- A `release/10.0.1xx` ref identifies a train/band, not the month it is servicing.
- A bootstrap SDK in `global.json` does not identify the release being shipped.
- Runtime product versions and SDK patch versions differ; use the mapping, not
  a guess that `10.0.4` means SDK branch `internal/release/10.0.104`.
- Release Specific can already exist while General Servicing still has the same
  branding. Check for a Release Specific branch for the approved release first.
- Branch name and branding that disagree, or stale/incomplete inventories, are
  conflicting evidence. Resolve the discrepancy rather than selecting a ref
  from its name alone.
- Window identity includes **year**, such as `2027/2B`. OOB rebranding can change
  product patch numbers without changing that window's identity.
- Intake can be frozen while a parking ref still exists. Obtain its current
  intake state and QB-published destination; a branch listing cannot prove this.
- During integration, the QB can publish General Servicing as the destination
  before its branding change merges. Do not override that handoff from branding.

If authorized access cannot establish a decisive fact, ask for it or the QB's
mapping. Do not ask for credentials or attempt a privilege workaround. Record
observation times and refs; recheck after any release transition.

## Branch links

Use the canonical repository browser URL returned by the host or verified remote
metadata, not a token-bearing clone URL:

- **GitHub:** append `/tree/<branch>` to the canonical repository URL. Use proper
  URL encoding for branch names; slashes in GitHub tree URLs may remain slashes.
- **Azure Repos:** append `?version=GB<encoded-branch>` to the verified HTTPS
  repository browser URL (or `&version=...` if it already has a query).
  URL-encode the branch, especially query delimiters and spaces; `GB` selects a
  branch. Slashes may be percent-encoded or left as slashes in this query value.
  Do not point to `refs/heads/` as part of the displayed branch name.

For an offline snapshot, use its supplied repository browser URL even when the
host or project is synthetic; do not request or invent a real one. Label the
link snapshot-based.

For an SSH remote, obtain the HTTPS browser URL from host metadata or the user;
do not guess an internal host/project mapping. Remove credential/userinfo
components before displaying a URL.

State that the branch link is the PR **base**. If one of several bands is
blocked, separate its pending result from verified targets.
