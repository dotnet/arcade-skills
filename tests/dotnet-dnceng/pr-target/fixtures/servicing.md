# Synthetic branch-state evidence

Observed 2027-01-15T12:00:00Z for an offline evaluation. This is a complete,
successful inventory of relevant public and authorized internal refs, including
the current QB window mapping and intake status. It contains no change approval.
Construct snapshot-based example branch links using the exercise URLs below;
these links do not claim verification against live endpoints.

Canonical public VMR: https://github.com/dotnet/dotnet
The checkout's origin is the developer's fork, mmitche/dotnet, not the PR base.
Internal VMR browser URL for the exercise: https://dev.azure.com/example/project/_git/vmr
Canonical public runtime component: https://github.com/dotnet/runtime

Verified public refs: main, release/10.0.1xx, release/10.0.2xx in the VMR;
main and release/10.0 in runtime. The runtime component's release/10.0 maps
to the VMR's 1xx shared-component train; runtime has no release/10.0.1xx ref.

| Window | Product release | 1xx Release Specific | 2xx Release Specific |
|--------|-----------------|----------------------|----------------------|
| 2026/12B | 10.0.3 | internal/release/10.0.103 | internal/release/10.0.200 |
| 2027/1B | 10.0.4 | absent | absent |
| 2027/2B | 10.0.5 | absent | absent |
| 2027/3B | 10.0.6 | absent | absent |
| 2026/11B | 10.0.2 | absent | absent |

Both bands' public and internal General Servicing represent 2027/1B (10.0.4):
release/10.0.1xx, internal/release/10.0.1xx, release/10.0.2xx,
internal/release/10.0.2xx. All four refs exist.

Verified parking refs:
- internal/parking/10.0.1xx/2027/2B
- internal/parking/10.0.2xx/2027/2B

Their intake is open. No parking integration is in progress.
No parking refs exist for 2027/3B. No parking refs exist for 2026/11B.
No other Release Specific branches match the windows above.

Verified OOB ref: internal/release/10.0.104-oob.1. Existence alone does not
constitute approval to use it.

The shared-component build configuration classifies runtime as shared (built
from source only in 1xx). SDK source changes are band-specific. There is no
policy or branch mapping for .NET 8 in this snapshot.
