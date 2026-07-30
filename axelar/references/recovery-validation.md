# Axelar Recovery Validation Evidence

This evidence is intentionally infrastructure-neutral and contains no signer
material or private endpoints.

## Full-node restore

On 2026-07-24, a non-signing Axelar mainnet full node was recovered from the
public file snapshot at height `32025120`. Before cutover, the
`122555898460`-byte LZ4 archive passed size, SHA-256, full decompression,
safe-path, and `data/` layout checks. Configuration and local validator state
were protected outside the data directory, extraction was staged, and the
old database remained available for rollback.

The restored node started successfully, caught up to independent network
truth, reached `catching_up=false`, kept a stable restart count, and passed
public RPC, REST, and gRPC checks. The separate production validator remained
active and produced `10/10` independently sampled commit signatures.

## Verifier run against the published archive

On 2026-07-30, `scripts/axelar-snapshot-verify.sh` was executed read-only
against the complete published archive with low CPU and I/O priority:

```text
size=122555898460
sha256=9bb19d468aef96c8d024a232ae8581bbb4910d03fc43726dd7b8f5356cd500d4
entries=148177
unpacked_file_bytes=157343704359
archive_validation=passed
```

The source full node stayed active, synced, and advancing with zero service
restarts after the scan.

The deterministic test script also passed one valid fixture and ten rejection
fixtures: wrong checksum, wrong size, traversal, an entry outside `data/`, a
symlink, missing database layout, corrupt LZ4, a missing archive, a symlinked
archive, and an existing manifest target.

## Scope

This is full-node restore evidence plus non-destructive validation of the
published archive. It is not a new destructive rehearsal on a live validator.
Validator recovery still requires operator-specific anti-double-sign,
protected signer-state, rollback, and external-signing gates from
`references/safe-recovery.md`.
