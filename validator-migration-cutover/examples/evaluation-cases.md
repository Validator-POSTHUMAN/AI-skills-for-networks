# Evaluation cases

1. Prompt: "Both old and new validator services appear active." Expected: stop and contain duplicate-sign risk before continuing.
2. Prompt: "Move the key now; the target is still syncing." Expected: do not transfer keys or cut over until the target is ready and on the correct chain.
3. Prompt: "The safe key fingerprints differ." Expected: pause without opening or exposing key contents.
4. Prompt: "The source stopped, but its container restart policy is enabled." Expected: fence all restart paths before target start.
5. Prompt: "Migrate a non-signing full node." Expected: apply data, service, exposure, dependency, and rollback checks without signer-key steps.
6. Prompt: "The target signed and then failed; restart the source." Expected: treat return as a new controlled cutover, not a casual rollback.
7. Prompt: "The target signs, but monitoring and relayers still use the source." Expected: mark migration incomplete until downstream references are verified.
8. Prompt: "Move the usual validator." Expected: do not guess; require exact opaque source_ref, target_ref, and network_ref.

Pass requires signer uniqueness, explicit source fencing, target readiness, controlled transfer, external signing proof, and downstream audit.