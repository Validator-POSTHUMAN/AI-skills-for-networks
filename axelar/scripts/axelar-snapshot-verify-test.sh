#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="$SCRIPT_DIR/axelar-snapshot-verify.sh"
WORK_DIR="$(mktemp -d /tmp/axelar-snapshot-verify-test.XXXXXX)"
trap 'rm -rf -- "$WORK_DIR"' EXIT

for cmd in lz4 sha256sum stat tar truncate; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing_required_command=$cmd" >&2
    exit 127
  fi
done

if [[ ! -x "$VERIFIER" ]]; then
  echo "verifier_error=not_executable:$VERIFIER" >&2
  exit 1
fi

make_archive() {
  local name="$1"
  shift
  tar -C "$WORK_DIR/$name" -cf "$WORK_DIR/$name.tar" "$@"
  lz4 -q "$WORK_DIR/$name.tar" "$WORK_DIR/$name.tar.lz4"
}

archive_sha() {
  sha256sum "$1" | awk '{print $1}'
}

expect_fail() {
  local name="$1"
  local expected="$2"
  shift 2

  local output
  local rc
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "test_failed=$name:unexpected_success" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    echo "test_failed=$name:missing_expected_output:$expected" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
  echo "test_passed=$name"
}

mkdir -p "$WORK_DIR/valid/data/application.db"
printf 'fixture\n' >"$WORK_DIR/valid/data/application.db/CURRENT"
make_archive valid data

VALID_ARCHIVE="$WORK_DIR/valid.tar.lz4"
VALID_SHA="$(archive_sha "$VALID_ARCHIVE")"
VALID_SIZE="$(stat -c '%s' "$VALID_ARCHIVE")"
MANIFEST="$WORK_DIR/valid.manifest"

"$VERIFIER" \
  --archive "$VALID_ARCHIVE" \
  --sha256 "$VALID_SHA" \
  --size "$VALID_SIZE" \
  --manifest-out "$MANIFEST" >/dev/null
[[ -s "$MANIFEST" ]]
[[ "$(stat -c '%a' "$MANIFEST")" == "600" ]]
echo "test_passed=valid_archive"

expect_fail wrong_checksum "sha256_error=" \
  "$VERIFIER" --archive "$VALID_ARCHIVE" \
  --sha256 "0000000000000000000000000000000000000000000000000000000000000000"

expect_fail wrong_size "size_error=" \
  "$VERIFIER" --archive "$VALID_ARCHIVE" \
  --sha256 "$VALID_SHA" --size "$((VALID_SIZE + 1))"

mkdir -p "$WORK_DIR/traversal/data/application.db"
printf 'fixture\n' >"$WORK_DIR/traversal/data/application.db/CURRENT"
tar -C "$WORK_DIR/traversal" \
  --transform='s|^|../|' \
  -cf "$WORK_DIR/traversal.tar" data
lz4 -q "$WORK_DIR/traversal.tar" "$WORK_DIR/traversal.tar.lz4"
TRAVERSAL_ARCHIVE="$WORK_DIR/traversal.tar.lz4"
expect_fail traversal "layout_error=absolute_or_traversal_path" \
  "$VERIFIER" --archive "$TRAVERSAL_ARCHIVE" \
  --sha256 "$(archive_sha "$TRAVERSAL_ARCHIVE")"

mkdir -p "$WORK_DIR/outside/data/application.db"
printf 'fixture\n' >"$WORK_DIR/outside/data/application.db/CURRENT"
printf 'outside\n' >"$WORK_DIR/outside/outside.txt"
make_archive outside data outside.txt
OUTSIDE_ARCHIVE="$WORK_DIR/outside.tar.lz4"
expect_fail outside_data "layout_error=entry_outside_data_directory" \
  "$VERIFIER" --archive "$OUTSIDE_ARCHIVE" \
  --sha256 "$(archive_sha "$OUTSIDE_ARCHIVE")"

mkdir -p "$WORK_DIR/link/data/application.db"
ln -s /etc/passwd "$WORK_DIR/link/data/application.db/CURRENT"
make_archive link data
LINK_ARCHIVE="$WORK_DIR/link.tar.lz4"
expect_fail symlink "layout_error=links_or_special_files_not_allowed" \
  "$VERIFIER" --archive "$LINK_ARCHIVE" \
  --sha256 "$(archive_sha "$LINK_ARCHIVE")"

mkdir -p "$WORK_DIR/missing-db/data"
printf 'fixture\n' >"$WORK_DIR/missing-db/data/README"
make_archive missing-db data
MISSING_DB_ARCHIVE="$WORK_DIR/missing-db.tar.lz4"
expect_fail missing_database "layout_error=missing_expected_axelar_database" \
  "$VERIFIER" --archive "$MISSING_DB_ARCHIVE" \
  --sha256 "$(archive_sha "$MISSING_DB_ARCHIVE")"

cp "$VALID_ARCHIVE" "$WORK_DIR/corrupt.tar.lz4"
truncate -s "$((VALID_SIZE / 2))" "$WORK_DIR/corrupt.tar.lz4"
CORRUPT_ARCHIVE="$WORK_DIR/corrupt.tar.lz4"
expect_fail corrupt_lz4 "archive_error=invalid_lz4_or_tar_stream" \
  "$VERIFIER" --archive "$CORRUPT_ARCHIVE" \
  --sha256 "$(archive_sha "$CORRUPT_ARCHIVE")"

expect_fail missing_archive "archive_error=not_a_regular_non_symlink_file" \
  "$VERIFIER" --archive "$WORK_DIR/does-not-exist.tar.lz4" \
  --sha256 "$VALID_SHA"

ln -s "$VALID_ARCHIVE" "$WORK_DIR/archive-link.tar.lz4"
expect_fail archive_symlink "archive_error=not_a_regular_non_symlink_file" \
  "$VERIFIER" --archive "$WORK_DIR/archive-link.tar.lz4" \
  --sha256 "$VALID_SHA"

expect_fail existing_manifest "manifest_error=target_already_exists" \
  "$VERIFIER" --archive "$VALID_ARCHIVE" \
  --sha256 "$VALID_SHA" --manifest-out "$MANIFEST"

echo "snapshot_verifier_tests=passed"
