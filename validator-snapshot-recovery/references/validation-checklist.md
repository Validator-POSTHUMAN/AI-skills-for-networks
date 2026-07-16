# Snapshot validation checklist

## Capacity
Required headroom includes archive, extraction, retained old data, temporary files, and safety margin. Check inodes as well as bytes.

## Artifact
- Correct chain/environment
- Height and freshness independently checked
- Version and database backend compatible
- Checksum/signature used when available
- Compression test passes
- Archive paths and layout inspected before cutover

## Validator safety
- Keys backed up outside deletion target
- Backup verified without opening secrets
- Existing signer stopped and fenced
- Signer state handled by a chain-specific rule
- External signing verification after recovery
