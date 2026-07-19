# Guarded workflow registry

The guarded workflow registry is a generic storage-kernel mechanism. It does
not belong to MoonDesk or any other product package, and it contains no
product, policy, or lifecycle-event vocabulary.

## Security boundary

`activate_guarded_workflow` is a trusted host bootstrap or migration
operation. On first activation, the host is responsible for selecting the real
authoritative mutation root and the ordered authoritative guard roots while OS
permissions prevent an attacker from replacing them. The registry then binds:

- the exact mutation workflow;
- each ordered guard workflow;
- the canonical absolute workspace and storage-root identities; and
- the mutation replay prefix observed at activation.

The declaration is published before its marker. Once a declaration exists,
raw mutation and official guarded capabilities fail closed if the marker is
missing or corrupt. Repeating the identical trusted activation can finish an
interrupted marker publication, but only when the recorded activation prefix
is still present. It does not require the current head to equal the activation
head, so later valid guarded appends do not prevent restart or reactivation.

Root identity is deliberately not portable. Copying or relocating a registered
filesystem store does not silently transfer authority. A future restore tool
must provide an explicit trusted verify-and-rebind operation; copying registry
files is not such an operation.

## Supported mutation paths

After activation, `MemoryStore::commit` and `FileSystemStore::commit` reject
the registered mutation workflow before idempotency or CAS processing. The
only official lifecycle mutation capability is a storage-owned
`GuardedMemoryStore` or `RegistryBoundFileSystemStore` constructed from the
opaque activation receipt. `RegistryBoundGuardedStoragePort` is sealed, so a
caller-composed `GuardedStoragePort` cannot satisfy that boundary.

Legacy unregistered workflows retain the existing raw and guarded APIs for
compatibility. First-party callers must activate each transaction domain before
using the official lifecycle commit API. Product packages must not persist,
decode, synthesize, or copy registry declarations, markers, bindings, or
activation receipts.

## Trusted computing base and limits

The trusted computing base is the storage package, its native filesystem stub,
the first-activation host operation, OS filesystem permissions, canonical path
resolution, and the process-safe workspace lock. An arbitrary external
`StoragePort` remains outside this trust boundary; the registry cannot prevent
a malicious implementation from writing to an unrelated backend. The sealed
official lifecycle capability prevents such an implementation from being
passed to `commit_lifecycle_candidate_v2`.
