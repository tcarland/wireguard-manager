#!/usr/bin/env bash
#
# test-wireconfig.sh - Test script for WireConfig Example
# Runs the commands from the README's WireConfig Example section
# and compares generated configs with the example directory.

set -e

PNAME=${0##*/}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TEST_DIR="./test"
EXAMPLE_DIR="./example"
BIN_DIR="./bin"

GENERATED_FILES=(
    "wg-mgr-server.yaml"
    "wg-mgr-client1.yaml"
    "wg-mgr-client2.yaml"
    "wg-mgr-client3.yaml"
)
WG_MGR_PUBKEY="$TEST_DIR/.wg_pub.key"
WG_MGR_PVTKEY="$TEST_DIR/.wg_pvt.key"

echo "=========================================="
echo "WireConfig Tests"
echo "=========================================="
echo ""

echo "-> Generating fake key pair..."

mkdir -p $TEST_DIR
echo "serverpubkey" > $WG_MGR_PUBKEY
echo "serverpvtkey" > $WG_MGR_PVTKEY
export WG_MGR_PUBKEY
export WG_MGR_PVTKEY

echo "-> Running WireConfig Example commands..."

./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" create 10.0.0.1/24
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" addPeer client1 10.0.0.2/24 client1pubkey
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" addPeer client2 10.0.0.3/24 client2pubkey
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" addNetwork wg1 10.0.1.1/24
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" -i wg1 addPeer client3 10.0.1.2/24 client3pubkey
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" -E server:55820 -k 30 createFrom client1 server1
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" -E server:55820 -k 30 createFrom client2 server1
./bin/wireconfig.sh -c "$TEST_DIR/wg-mgr-server.yaml" -o "$TEST_DIR" -E server:55820 -k 30 -i wg1 createFrom client3 server1

echo -e "${GREEN}✓ All wireconfig commands completed${NC}"
echo ""


echo "-> Comparing generated configs with examples..."
echo "=========================================="
FAILED=false
TOTAL=0
PASSED=0

for file in "${GENERATED_FILES[@]}"; do
    TOTAL=$((TOTAL + 1))
    echo ""
    echo "Comparing: $file"
    echo "------------------------------------------"

    GENERATED="$TEST_DIR/$file"
    EXPECTED="$EXAMPLE_DIR/$file"

    if [ ! -f "$EXPECTED" ]; then
        echo -e "${YELLOW}WARNING: Expected file not found: $EXPECTED${NC}"
        continue
    fi

    if diff -u "$EXPECTED" "$GENERATED"; then
        echo -e "${GREEN}✓ PASS: $file matches expected output${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL: $file differs from expected output${NC}"
        echo "Expected file: $EXPECTED"
        echo "Generated file: $GENERATED"
        FAILED=true
    fi
done

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo "Total files compared: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $((TOTAL - PASSED))"
echo ""

if [ "$FAILED" = true ]; then
    echo -e "${RED}TEST SUITE FAILED${NC}"
    echo ""
    echo "Generated files are available at: $TEST_DIR"
    echo "Expected files are at: $EXAMPLE_DIR"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED ✓${NC}"
    exit 0
fi
