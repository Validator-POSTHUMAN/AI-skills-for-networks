# Source and version verification

Use current authenticated coordinator inputs for the running cohort, and
version-pinned source for implementation behavior. Public documentation can
describe a reference devnet rather than the invited validator cohort.

## Source map

- [Validator onboarding](https://junoclaw.xyz/docs/onboarding/validators/):
  public onboarding baseline, not an independent live roster or GO.
- [Run-a-node reference](https://junoclaw.xyz/docs/reference/run-a-node/):
  public node setup; compare its chain and config format with your cohort.
- [Release list](https://github.com/Dragonmonk111/layer-sdk/releases):
  candidate artifacts and metadata; do not install the newest release merely
  because it is newer than the running coordinator-approved build.

Record source URL, immutable commit/tag and observed date, artifact SHA-256,
publisher-authentication evidence, actual executable digest, protocol/era,
schema and coordinator approval in the private operator inventory.
Mark authentication unavailable if it cannot be established. A checksum next
to an unauthenticated download establishes only byte agreement.

Do not execute node binaries to discover arbitrary flags. Historical builds
of slay3rd accept a positional configuration path and do not implement a
conventional --version flag. Obtain command semantics from the exact source
and authenticated package, or inspect a verified tool in an isolated environment.

## Immutable source baseline reviewed

The read-only query recipes were checked against full commit
[e0f89a1420e15f067acf3f9b47e565e210f1a85a](https://github.com/Dragonmonk111/layer-sdk/tree/e0f89a1420e15f067acf3f9b47e565e210f1a85a)
resolved from [slay3rd-rc18v3](https://github.com/Dragonmonk111/layer-sdk/releases/tag/slay3rd-rc18v3).
This is a documentation baseline, not the approved deployed fleet commit.
The release object is not immutable; retain full source pins rather than
assuming a tag will never move. Release-to-binary reproducibility was not
established by this review.

That release lists two distinct assets: slay3rd and slay3rd-rc18v3, with
*different* API-reported digests. Select the exact approved asset as well as
its digest; a version label alone is not an artifact identity. The API-reported
SHA-256 values are respectively
069266c3379f2fa0dbde6af6884f445653b2a1d910961fb0fd1589fb90d5ac77 and
a99d4629cdbbf2f75e1da4f546d8d5ec07a627e66b0fa03f504a3d26720b8ba1.
They are not independent downloaded-byte or publisher-signature verification.

The public setup documentation also carries historical source pin
[90451d843b71372addcb761e0ecf1cb55998f50f](https://github.com/Dragonmonk111/layer-sdk/tree/90451d843b71372addcb761e0ecf1cb55998f50f).
It has query payload/reflection support but lacks the reviewed certs tally
subcommand and metrics_listen option. Do not mix instructions from these pins.
Metrics listen configuration is optional; do not assume a metrics port exists.

Current fleet build, roster, threshold and operator-to-participant mapping
must come from authenticated current operator inputs. Public explorer counts
alone establish none of those. Read [queries and verifier limits](queries.md)
before attributing a certificate bit or interpreting state roots.

## Historical boundaries to revalidate

- JunoClaw G2 used chain ID junoclaw-g1; a reference devnet used junoclaw-1.
  Neither is a safe default for another cohort.
- G2 round 2 used eight seats, threshold six and five dealers. Subsequent eras
  may change all three and the seat-index mapping.
- State-sync quorum behavior and halted-chain/force options are release
  dependent. Preserve the normal fail-closed path unless the exact exception
  is reviewed and authorized.
- Certificate layouts, bitmap order and application payload encoding are
  version-specific. Do not copy an offset from an incident note into a verifier.
- A peer mesh warning may measure recent authenticated payload activity rather
  than active TCP sessions. Check that metric's implementation before treating
  it as a connection count.

Use [operations](operations.md) for evidence levels and
[ceremony gates](ceremony.md) for key/share boundaries.
