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

Internal General Servicing, Release Specific, and parking destinations are VMR
branches. A component's internal validation branch can validate a change but
does not replace that final VMR destination.

For each band, read current branding/version files at the observed ref SHA
(file locations vary by release). Combine that with the release/QB's current
window-to-branch mapping:

- A `release/10.0.1xx` ref identifies a train/band, not the month it is servicing.
- A bootstrap SDK in `global.json` does not identify the release being shipped.
- Runtime product versions and SDK patch versions differ; use the mapping, not
  a guess that `10.0.4` means SDK branch `internal/release/10.0.104`.
- Release Specific can already exist while General Servicing still has the same
  branding. Check the Release Specific mapping first.
- Window identity includes **year**, such as `2027/2B`. OOB rebranding can change
  product patch numbers without changing that window's identity.
- Intake can be frozen while a parking ref still exists. Obtain its current
  intake state and QB-published destination; a branch listing cannot prove this.
- During integration, the QB can publish General Servicing as the destination
  before its branding change merges. Do not override that handoff from branding.

If authorized access cannot establish a decisive fact, ask for that fact or the
QB's mapping. Do not ask for credentials, attempt a privilege workaround, or
report an unverified candidate as ready for PR creation. Record observation
times and refs; recheck after any release transition.

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

For an SSH remote, obtain the HTTPS browser URL from host metadata or the user;
do not guess an internal host/project mapping. Remove credential/userinfo
components before displaying a URL.

Output a branch link and state that it is the PR **base**. No branch link is
appropriate when approval, ref existence, visibility, or a frozen-intake
handoff is still unresolved. If one of several bands is blocked, clearly
separate its pending result from verified targets.
