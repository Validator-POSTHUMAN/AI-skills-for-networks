# Public service release gates

## Source gate
- Correct owning repository and branch
- Schema and naming conventions validated
- Diff contains no private infrastructure or secrets
- Public commands and endpoints verified
- Reviewed PR used for publication

## Deployment gate
- Exact target resolved from private knowledge
- Known-good revision captured
- Intended commit pulled
- Documented cache only cleared
- Build passes before process replacement

## Verification gate
- Process healthy and stable
- Changed pages and representative controls return successfully
- New content present; stale content absent from full payload
- Images, tabs, links, downloads, and endpoints work
- Rollback point and propagation state recorded
