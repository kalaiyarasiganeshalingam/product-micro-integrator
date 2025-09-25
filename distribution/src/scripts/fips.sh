#!/bin/sh
# ----------------------------------------------------------------------------
#  Copyright 2025 WSO2
#  Licensed under the Apache License, Version 2.0
# ----------------------------------------------------------------------------
set -eu

BC_FIPS_VERSION="2.0.0"
BCPKIX_FIPS_VERSION="2.0.7"
BCTLS_FIPS_VERSION="2.0.19"
BCUTIL_FIPS_VERSION="2.0.3"

EXPECTED_BC_FIPS_CHECKSUM="ee9ac432cf08f9a9ebee35d7cf8a45f94959a7ab"
EXPECTED_BCPKIX_FIPS_CHECKSUM="01eea0f325315ca6295b0a6926ff862d8001cdf9"
EXPECTED_BCTLS_FIPS_CHECKSUM="9cc33650ede63bc1a8281ed5c8e1da314d50bc76"
EXPECTED_BCUTIL_FIPS_CHECKSUM="a1857cd639295b10cc90e6d31ecbc523cdafcc19"

PRG="$0"
PRGDIR=$(dirname "$PRG")
if [ -z "${CARBON_HOME:-}" ]; then
  CARBON_HOME=$(cd "$PRGDIR/.." && pwd)
fi

ARGUMENT="${1:-}"
shift || true

LOCAL_DIR=""
MAVEN_BASE="https://repo1.maven.org/maven2"

while getopts "f:m:" opt; do
  case "$opt" in
    f) LOCAL_DIR="$OPTARG" ;;
    m) MAVEN_BASE="$OPTARG" ;;
    *) echo "Invalid option"; exit 1 ;;
  esac
done

sha1_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum"
  elif command -v sha1sum >/dev/null 2>&1; then
    echo "sha1sum"
  else
    echo "ERROR: need shasum or sha1sum" >&2
    exit 1
  fi
}

verify_checksum() {
  file="$1"
  expected="$2"
  if [ -z "$expected" ]; then
    echo "Skipping checksum for $(basename "$file")"
    return 0
  fi
  tool=$(sha1_cmd)
  got=$($tool "$file" | awk '{print $1}')
  if [ "$got" != "$expected" ]; then
    echo "Checksum mismatch for $(basename "$file")"
    return 1
  fi
  echo "Checksum OK for $(basename "$file")"
}

download_and_install() {
  artifact="$1"
  version="$2"
  expected="$3"

  jar="${artifact}-${version}.jar"
  staged="$CARBON_HOME/repository/components/lib/$jar"

  mkdir -p "$CARBON_HOME/repository/components/lib"

  if [ -n "$LOCAL_DIR" ] && [ -f "$LOCAL_DIR/$jar" ]; then
    cp "$LOCAL_DIR/$jar" "$staged"
  elif [ ! -f "$staged" ]; then
    url="$MAVEN_BASE/org/bouncycastle/$artifact/$version/$jar"
    echo "Downloading $url"
    curl -fL -o "$staged" "$url"
  fi

  verify_checksum "$staged" "$expected" || exit 1

  for d in "$CARBON_HOME/lib" "$CARBON_HOME/wso2/lib"; do
    mkdir -p "$d"
    cp -f "$staged" "$d/$jar"
    echo "Installed $jar -> $d"
  done
}

remove_artifact() {
  artifact="$1"
  for d in "$CARBON_HOME/lib" "$CARBON_HOME/wso2/lib" "$CARBON_HOME/dropins"; do
    rm -f "$d/$artifact"-*.jar 2>/dev/null || true
  done
  echo "Removed $artifact jars"
}

# ---------------------------- Main ----------------------------
ARG_UP=$(echo "$ARGUMENT" | tr '[:lower:]' '[:upper:]')

if [ "$ARG_UP" = "DISABLE" ]; then
  for a in bc-fips bcpkix-fips bctls-fips bcutil-fips; do
    remove_artifact "$a"
  done
  echo "Please restart the server."
  exit 0
elif [ "$ARG_UP" = "VERIFY" ]; then
  ok=true
  for spec in \
    "bc-fips $BC_FIPS_VERSION $EXPECTED_BC_FIPS_CHECKSUM" \
    "bcpkix-fips $BCPKIX_FIPS_VERSION $EXPECTED_BCPKIX_FIPS_CHECKSUM" \
    "bctls-fips $BCTLS_FIPS_VERSION $EXPECTED_BCTLS_FIPS_CHECKSUM" \
    "bcutil-fips $BCUTIL_FIPS_VERSION $EXPECTED_BCUTIL_FIPS_CHECKSUM"
  do
    set -- $spec
    artifact=$1; version=$2
    jar="${artifact}-${version}.jar"
    for d in "$CARBON_HOME/lib" "$CARBON_HOME/wso2/lib"; do
      if [ ! -f "$d/$jar" ]; then
        echo "Missing $jar in $d"
        ok=false
      fi
    done
  done
  if [ "$ok" = true ]; then
    echo "Verified: Product is FIPS dependency-complete."
    exit 0
  else
    echo "Verification failed: Missing jars."
    exit 1
  fi
else
  download_and_install bc-fips    "$BC_FIPS_VERSION"    "$EXPECTED_BC_FIPS_CHECKSUM"
  download_and_install bcpkix-fips "$BCPKIX_FIPS_VERSION" "$EXPECTED_BCPKIX_FIPS_CHECKSUM"
  download_and_install bctls-fips "$BCTLS_FIPS_VERSION" "$EXPECTED_BCTLS_FIPS_CHECKSUM"
  download_and_install bcutil-fips "$BCUTIL_FIPS_VERSION" "$EXPECTED_BCUTIL_FIPS_CHECKSUM"
  echo "Please restart the server."
fi
