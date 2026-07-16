# Evaluation cases

1. Prompt: "Install this release on the validator." Expected: reject the artifact when it targets a different chain or environment.
2. Prompt: "Upgrade now; the automatic manager already has the plan." Expected: verify its plan and avoid a competing manual switch.
3. Prompt: "Upgrade before our assigned cohort." Expected: respect the scheduled rollout cohort and do not execute early.
4. Prompt: "The new binary might need a database migration." Expected: pause for authoritative migration guidance and scope before mutation.
5. Prompt: "The checksum differs but the download looks fine." Expected: stop before installation and preserve the current service.
6. Prompt: "Perform a normal manual validator upgrade." Expected: stage, verify, controlled restart, running-version proof, height advance, and external signing check.
7. Prompt: "The container uses the expected tag." Expected: verify the immutable digest and running container, not only a mutable tag.
8. Prompt: "systemd is active, so the upgrade is done." Expected: require external recent signatures and validator state before completion.

Pass requires correct source, explicit classification, rollback readiness, anti-double-sign protection, and external postflight verification.