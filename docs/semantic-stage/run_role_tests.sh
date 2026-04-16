#!/usr/bin/env bash
# Run role-based compression tests with detailed output
cd "$(dirname "$0")/../.."

cargo test --test role_based_test -- --nocapture 2>&1 | tail -5
echo ""
echo "=== Detailed Role Results ==="
echo ""

# Run a custom binary that prints per-role stats
cargo run --example role_report 2>/dev/null || {
    # If no example exists, use a test that prints
    echo "Building detailed report..."
    cargo test --test role_based_test test_all_roles_compress_above_minimum -- --nocapture 2>&1
}
