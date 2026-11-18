# Synthetic 1xx branch and branding evidence

Observed 2027-01-15T12:00:00Z in an offline exercise. Use the supplied
repository URLs to construct snapshot-based example links; they are not
claims about live endpoints.

Canonical public VMR: https://github.com/dotnet/dotnet
Internal VMR browser URL: https://dev.azure.com/example/project/_git/vmr

A successful, complete 1xx inventory found public `release/10.0.1xx`,
internal `internal/release/10.0.1xx`, and one internal Release Specific branch,
`internal/release/10.0.104`. All three refs exist. There are no other 1xx
Release Specific or OOB refs. A complete parking-ref inventory found no 1xx
parking refs, and no parking integration is in progress.

Exact copies of `eng/Versions.props` at the observed refs are provided:

- Both public and internal General Servicing: `refs/general/eng/Versions.props`.
- Internal `internal/release/10.0.104`: `refs/release-specific/eng/Versions.props`.

The inventory does not relate calendar windows to SDK versions; any such
relationship in the request comes from the stated Tactics approval.
