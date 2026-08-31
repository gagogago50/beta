#!/usr/bin/env bash
set -u
export PATH="/home/user/flutter/bin:$HOME/.cargo/bin:$PATH"
export RUSTFLAGS="-C debuginfo=0"
export CARGO_PROFILE_DEV_DEBUG=0
cd /home/user/nek0-personal

echo "==== cargo fmt ===="
cargo fmt --manifest-path native/Cargo.toml -- --check && echo "FMT_OK" || echo "FMT_FAIL"

echo "==== cargo check (j=1) ===="
cargo check --locked --manifest-path native/Cargo.toml -p tsclient -j 1 2>&1 | tail -30
echo "CHECK_EXIT=${PIPESTATUS[0]}"

echo "==== flutter pub get ===="
(cd /home/user/nek0-personal && flutter pub get) 2>&1 | tail -15
echo "PUBGET_EXIT=${PIPESTATUS[0]}"

echo "==== flutter gen-l10n ===="
(cd /home/user/nek0-personal && flutter gen-l10n) 2>&1 | tail -15
echo "GENL10N_EXIT=${PIPESTATUS[0]}"
echo "VALIDATE_PHASE22_DONE"
