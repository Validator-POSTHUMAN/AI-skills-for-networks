# Upgrade verification checklist

## Source
- Official release/tag or signed distribution
- Correct network/environment
- Architecture and packaging match
- Checksum/signature verified when supplied
- Release notes and migrations reviewed

## Safety
- Freeze and rollout cohort checked
- Signing health established before stop
- Rollback artifact/config captured
- Disk and database compatibility checked
- No duplicate signer can start

## Postflight
- Running version verified from process or API
- Height advances and sync is healthy
- Validator status and recent signatures verified externally
- Monitoring, relayers, sentries, and consumers checked
- Documentation and watch period recorded
