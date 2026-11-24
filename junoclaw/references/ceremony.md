# Threshold ceremony gates

Resolve the current round, players, dealers, threshold, full previous group
public key, tool fingerprint and approved handoff route before execution.
Historical 8-seat / 6-of-8 / 5-dealer G2 values are not defaults.

This checklist deliberately contains no paste-ready key-generation, dealer-log,
finalize or key-replacement commands. Those actions require the authenticated
round package and exact pinned tool syntax; they must not be guessed.

## Artifact classification

| Artifact | Handling |
| --- | --- |
| Public identity request, public dealing, accepted acknowledgement, reviewed dealer log | Inspect exact fields; transmit only through the approved ceremony route after classification |
| Recipient-sealed private dealing | Only named recipient/approved relay; encrypted does not mean public |
| Live keys, intermediate BLS share, dealer seed, passwords | Keep on the authorized signer; never load contents into an AI context or public output |
| Roster, node configuration and operational reports | Keep private by default; configuration can include management addresses or sensitive paths |

## Ordered gates

1. **Intake:** authenticate the publisher and pin archive/tool hashes. Reject
   absolute/traversal members, links, devices, unexpected files and wrong
   recipients before extraction. Hash agreement is not publisher authentication.
2. **Dealing:** retain dealer entropy locally; verify recipient membership.
   Do not generate a replacement identity for an existing seat as a shortcut.
3. **Acknowledgement:** verify every expected player/dealer pair exactly once,
   matching round and identity, with no unresolved complaint. Counts alone do
   not prove coverage: a duplicate can conceal a missing pair.
4. **Dealer logging:** require every acknowledgement expected by this round's
   protocol, its validation and coordinator acceptance before the dealer logs.
   Missing/disputed acknowledgements can cause share disclosure. Never run the
   logging command merely to see its output.
5. **Observation:** independently verify complete logs, approved threshold and
   exact full group-key continuity where the reshare requires it. A displayed
   key prefix or success message is insufficient.
6. **Finalization:** on the sole approved signer, use protected same-host staging;
   verify the new index/share against the current roster without exporting
   secret contents. Finalization is not authorization to replace the live key.
7. **Activation:** follow the coordinated cutover in [operations](operations.md).
   Reconfirm active era and index before interpreting participation evidence.

Retain seed/intermediate material under the approved retention plan until
protocol verification and authorized cleanup permit removal. Public logs are
not automatically safe when complaint/acknowledgement gates failed.
