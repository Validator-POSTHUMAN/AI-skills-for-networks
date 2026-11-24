# Version-pinned read-only queries

These recipes are source-verified against [rc18v3 source commit e0f89a1420e15f067acf3f9b47e565e210f1a85a](https://github.com/Dragonmonk111/layer-sdk/tree/e0f89a1420e15f067acf3f9b47e565e210f1a85a), not an upgrade recommendation or a claim about your installed build. Resolve the actual cohort, protocol and authorized endpoints first. Tools must already be installed; no dependency installation, signer access or service restart is implied. Public HTTP routes were observed responding during source review; gRPC recipes were not runtime-tested against a validator.

## Public status versus local evidence

~~~sh
curl --fail --silent --show-error --max-time 10 'https://status.junoclaw.xyz/api/status' |
  jq '{height,height_age_s,sequence,tip_age_s,latest,seats}'

curl --fail --silent --show-error --max-time 10 'https://explorer.junoclaw.xyz/api/status'

curl --fail --silent --show-error --max-time 10 'https://explorer.junoclaw.xyz/api/blocks?n=200' |
  jq '[.[] | select(.finalized == true and .hybrid_cert == true) | {height,digest,state_root,participants,signers,mayo_sigs,cert_bytes}]'
~~~

These are endpoint-reported observations, not independent signature verification. In the pinned [explorer implementation](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/tools/jc-explorer/src/main.rs#L58-L96), finalized means certificate bytes are nonempty. The status API's deprecated tip field is a state sequence, not the explorer's block height; do not compare them as heights. A public monitor is a reference, not proof that the local process is current.

## Local committed height

Use the real private local endpoint from inventory, not an unapproved public port. The loopback address below is a reference example.

~~~sh
grpcurl -plaintext -connect-timeout 5 -max-time 10 -d '{}' 127.0.0.1:9090 layer.lightclient.v1.Query/LatestHeight
~~~

Repeat after about 60 seconds as a bounded check and compare height/time, then establish certified finality and seat participation separately. Query success alone is not a signing receipt. For an approved TLS reference, omit -plaintext; the public documentation names api.junoclaw.xyz:443, but reachability/support must be checked at use time.

The pinned [query schema](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/proto/layer/lightclient/v1/query.proto#L9-L58) is authoritative for method and field names. If reflection is unavailable, use a matching already-reviewed source checkout with grpcurl -import-path /path/to/reviewed-checkout/proto -proto layer/lightclient/v1/query.proto. A protobuf HTTP annotation does not prove a REST gateway is deployed.

## Compare one common explicit height

Replace REPLACE_WITH_COMMON_FINALIZED_HEIGHT with one shared decimal integer within both endpoints' retained windows. Do not use independent latest tips for this comparison.

~~~sh
grpcurl -plaintext -connect-timeout 5 -max-time 10 \
  -d '{"height":"REPLACE_WITH_COMMON_FINALIZED_HEIGHT"}' 127.0.0.1:9090 \
  layer.lightclient.v1.Query/Block
~~~

Response fields at this source pin: height, timestampNanos, proposalBytes, certificateBytes, payloadBytes. Protobuf uint64 values are decimal strings and bytes are base64. The [handler](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/app/slay3rd/src/grpc.rs#L477-L551) can return a payload-only success; require nonempty proposal and certificate before treating a record as finality evidence. A missing pruned record is not automatically a divergent chain.

Pipe a successful Block response to this local consistency parser, once for each authorized endpoint at the same height:

~~~sh
python3 -c '
import sys,json,base64,hashlib
r=json.load(sys.stdin)
def field(name):
    return base64.b64decode(r.get(name,""), validate=True)
p=field("payloadBytes")
proposal=field("proposalBytes")
cert=field("certificateBytes")
if not p or not proposal or not cert:
    raise SystemExit("INCOMPLETE: payload/proposal/certificate required")
print(json.dumps({"height":r["height"],
    "payload_sha256":hashlib.sha256(p).hexdigest(),
    "proposal_bytes":len(proposal),"certificate_bytes":len(cert)},sort_keys=True))
'
~~~

Require equal explicit heights and full 64-hex payload digests. This matches the pinned [payload digest definition](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/app/slay3rd/src/block.rs#L10-L60), but is only byte consistency/presence checking, not proof verification. Also authenticate chain/era/roster and verify the certificates. The payload state_root at H commits state after H-1; do not call it H's post-execution app hash. The source's digest-report.sh truncates digests to 16 hex characters and is not a substitute for this full-digest gate.

## Participation mapping and verifier limits

At this pin the node [sorts Ed25519 public keys](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/app/slay3rd/src/main.rs#L829-L855). Raw certificate bit positions use that participant order, not necessarily configured validator_index. Require an authenticated public roster mapping between operator identity, configured index and participant bit. Never inspect secret keys.json to obtain a public mapping.

An already-reviewed matching verify-cert can tally a bounded private log stream:

~~~sh
journalctl -u example-junoclaw.service --since '-5 minutes' -o cat --no-pager |
  verify-cert certs --last 500 --json
~~~

Replace the service name from inventory. Keep raw logs in the local pipe and review only sanitized output. The [tally implementation](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/tools/verify-cert/src/main.rs#L262-L387) returns source, certs, participants, per_index, masks and parse_failures. Require a nonempty sample, inspect parse failures, bind observations to one era and label the result decoded inclusion, not verified signing. A locally logged/parsed certificate alone is not independent peer evidence.

For stronger verification, use fresh independent records and authenticated public-only committee material to verify the classical and MAYO halves, correct chain/era, payload, signer uniqueness and quorum. This reference intentionally gives no automatic full-verification command: the exact public inputs and message binding must be reviewed for the release. The pinned [verifier](https://github.com/Dragonmonk111/layer-sdk/blob/e0f89a1420e15f067acf3f9b47e565e210f1a85a/tools/verify-cert/src/main.rs#L649-L685) can report success while saying PQ half: NOT verified. Its missing threshold can default to zero: require the explicit current positive threshold_required. Never pass a live private key file to --keys-file; a separately constructed authenticated public-only committee input is required.
