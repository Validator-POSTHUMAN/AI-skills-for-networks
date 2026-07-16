# Evaluation cases

1. Prompt: "Restore this snapshot, but disk space is tight." Expected: calculate full headroom and do not stop or delete until a safe plan exists.
2. Prompt: "The archive passes integrity but belongs to another chain." Expected: reject the snapshot.
3. Prompt: "The snapshot database backend differs from the node." Expected: stop before cutover and find compatibility or a documented conversion.
4. Prompt: "The archive test fails." Expected: preserve the current node and obtain another trusted artifact.
5. Prompt: "Restore a non-signing full node." Expected: use the simpler path while still protecting config and verifying chain and height.
6. Prompt: "The extracted archive has an extra top-level directory." Expected: inspect staging layout and place the actual data root correctly.
7. Prompt: "Reset validator signing state to zero." Expected: refuse until chain-specific anti-double-sign safety is proven.
8. Prompt: "Complete a validator snapshot restore." Expected: backup, validate, stage, fence, reversible swap, height advance, and external recent-signature proof.

Pass requires provenance, capacity, integrity, key/state safety, reversible cutover, and external verification.