#!/usr/bin/env bash
set -euo pipefail

ARCHIVE=""
EXPECTED_SHA256=""
EXPECTED_SIZE=""
MANIFEST_OUT=""

usage() {
  cat <<'USAGE'
Usage:
  axelar-snapshot-verify.sh \
    --archive <snapshot.tar.lz4> \
    --sha256 <expected-sha256> \
    [--size <expected-bytes>] \
    [--manifest-out <path>]

Validates a fully downloaded Axelar snapshot before any node service is
stopped or live data is replaced. The archive must:

- match the operator-supplied SHA-256;
- pass a complete LZ4 integrity scan;
- contain only regular files/directories under data/;
- contain no absolute paths, traversal, links, devices, sockets, or pipes;
- include an Axelar/CometBFT database layout.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE="$2"; shift 2 ;;
    --sha256) EXPECTED_SHA256="${2,,}"; shift 2 ;;
    --size) EXPECTED_SIZE="$2"; shift 2 ;;
    --manifest-out) MANIFEST_OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$ARCHIVE" || -z "$EXPECTED_SHA256" ]]; then
  usage >&2
  exit 2
fi

if [[ ! "$EXPECTED_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "invalid_sha256=expected_64_lowercase_hex" >&2
  exit 2
fi

if [[ -n "$EXPECTED_SIZE" ]] && { [[ ! "$EXPECTED_SIZE" =~ ^[0-9]+$ ]] || [[ "$EXPECTED_SIZE" -lt 1 ]]; }; then
  echo "invalid_size=expected_positive_integer" >&2
  exit 2
fi

for cmd in install lz4 mkfifo mktemp python3 readlink sha256sum stat tee; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing_required_command=$cmd" >&2
    exit 127
  fi
done

if [[ ! -e "$ARCHIVE" || -L "$ARCHIVE" ]]; then
  echo "archive_error=not_a_regular_non_symlink_file" >&2
  exit 1
fi

if ! ARCHIVE_REAL="$(readlink -f -- "$ARCHIVE")" || [[ ! -f "$ARCHIVE_REAL" ]]; then
  echo "archive_error=not_a_regular_non_symlink_file" >&2
  exit 1
fi

ACTUAL_SIZE="$(stat -c '%s' -- "$ARCHIVE_REAL")"
if [[ -n "$EXPECTED_SIZE" && "$ACTUAL_SIZE" != "$EXPECTED_SIZE" ]]; then
  echo "size_error=expected_${EXPECTED_SIZE}_got_${ACTUAL_SIZE}" >&2
  exit 1
fi

if [[ -n "$MANIFEST_OUT" && ( -e "$MANIFEST_OUT" || -L "$MANIFEST_OUT" ) ]]; then
  echo "manifest_error=target_already_exists" >&2
  exit 1
fi

VERIFY_DIR="$(mktemp -d /tmp/axelar-snapshot-verify.XXXXXX)"
cleanup() {
  rm -rf -- "$VERIFY_DIR"
}
trap cleanup EXIT

NAMES_FILE="$VERIFY_DIR/names.txt"
STATS_FILE="$VERIFY_DIR/stats.txt"
SHA_FIFO="$VERIFY_DIR/sha256.fifo"
SHA_FILE="$VERIFY_DIR/sha256.txt"
VALIDATOR="$VERIFY_DIR/validate_tar.py"

cat >"$VALIDATOR" <<'PY'
import posixpath
import sys
import tarfile

names_path, stats_path = sys.argv[1:3]
entry_count = 0
unpacked_bytes = 0
database_file_found = False

try:
    with open(names_path, "w", encoding="utf-8", newline="\n") as names:
        with tarfile.open(fileobj=sys.stdin.buffer, mode="r|") as archive:
            for member in archive:
                name = member.name
                try:
                    name.encode("utf-8")
                except UnicodeEncodeError:
                    raise ValueError("layout_error=non_utf8_path")
                if any(ord(char) < 32 or ord(char) == 127 for char in name):
                    raise ValueError("layout_error=control_character_in_path")
                if posixpath.isabs(name):
                    raise ValueError("layout_error=absolute_or_traversal_path")

                normalized = name
                while normalized.startswith("./"):
                    normalized = normalized[2:]
                normalized = normalized.rstrip("/")
                parts = normalized.split("/")
                if normalized == ".." or ".." in parts:
                    raise ValueError("layout_error=absolute_or_traversal_path")
                if normalized and normalized != "data" and not normalized.startswith("data/"):
                    raise ValueError("layout_error=entry_outside_data_directory")
                if not (member.isfile() or member.isdir()):
                    raise ValueError("layout_error=links_or_special_files_not_allowed")

                if member.isfile():
                    unpacked_bytes += member.size
                    if any(
                        normalized.startswith(f"data/{db}/") and
                        normalized != f"data/{db}/"
                        for db in ("application.db", "blockstore.db", "state.db")
                    ):
                        database_file_found = True

                names.write(name + "\n")
                entry_count += 1
except (tarfile.TarError, EOFError) as exc:
    print(f"archive_error=invalid_tar_stream:{type(exc).__name__}", file=sys.stderr)
    raise SystemExit(1)
except ValueError as exc:
    print(str(exc), file=sys.stderr)
    raise SystemExit(1)

if entry_count == 0:
    print("layout_error=empty_archive", file=sys.stderr)
    raise SystemExit(1)
if not database_file_found:
    print("layout_error=missing_expected_axelar_database", file=sys.stderr)
    raise SystemExit(1)

with open(stats_path, "w", encoding="ascii") as stats:
    stats.write(f"{entry_count} {unpacked_bytes}\n")
PY

mkfifo -m 600 "$SHA_FIFO"
sha256sum <"$SHA_FIFO" >"$SHA_FILE" &
SHA_PID=$!

set +e
tee "$SHA_FIFO" <"$ARCHIVE_REAL" |
  lz4 -q -dc |
  python3 "$VALIDATOR" "$NAMES_FILE" "$STATS_FILE"
PIPE_RC=$?
wait "$SHA_PID"
SHA_RC=$?
set -e

if [[ "$PIPE_RC" -ne 0 || "$SHA_RC" -ne 0 ]]; then
  echo "archive_error=invalid_lz4_or_tar_stream" >&2
  exit 1
fi

read -r ACTUAL_SHA256 _ <"$SHA_FILE"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "sha256_error=expected_${EXPECTED_SHA256}_got_${ACTUAL_SHA256}" >&2
  exit 1
fi

read -r ENTRY_COUNT UNPACKED_BYTES <"$STATS_FILE"
if [[ ! "$ENTRY_COUNT" =~ ^[0-9]+$ || ! "$UNPACKED_BYTES" =~ ^[0-9]+$ ]]; then
  echo "archive_error=invalid_validation_stats" >&2
  exit 1
fi

if [[ -n "$MANIFEST_OUT" ]]; then
  install -m 600 -- "$NAMES_FILE" "$MANIFEST_OUT"
fi

echo "archive=$ARCHIVE_REAL"
echo "size=$ACTUAL_SIZE"
echo "sha256=$ACTUAL_SHA256"
echo "entries=$ENTRY_COUNT"
echo "unpacked_file_bytes=$UNPACKED_BYTES"
echo "archive_validation=passed"
