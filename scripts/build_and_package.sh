#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build_and_package.sh [--format auto|deb|rpm|both] [--version X.Y.Z]

Builds rmp-eval using CMake Release config and packages the binary.

Options:
  --format   Packaging format (default: auto)
             auto = build all available package formats on this system
             deb  = build .deb only
             rpm  = build .rpm only
             both = build both .deb and .rpm (requires both toolchains)
  --version  Package version override (default: from scripts/get_version.sh)
  --help     Show this help text
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

FORMAT="auto"
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$("${REPO_ROOT}/scripts/get_version.sh")"
fi

if [[ "$FORMAT" != "auto" && "$FORMAT" != "deb" && "$FORMAT" != "rpm" && "$FORMAT" != "both" ]]; then
  echo "Invalid --format '$FORMAT' (expected auto|deb|rpm|both)" >&2
  exit 1
fi

major_from_compiler() {
  local compiler="$1"
  "$compiler" -dumpfullversion -dumpversion 2>/dev/null | awk -F. '{print $1}'
}

select_compilers() {
  local n
  for (( n=20; n>=12; n-- )); do
    if command -v "gcc-${n}" >/dev/null 2>&1 && command -v "g++-${n}" >/dev/null 2>&1; then
      echo "gcc-${n};g++-${n}"
      return 0
    fi
  done

  if command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1; then
    local gcc_major
    local gxx_major
    gcc_major="$(major_from_compiler gcc)"
    gxx_major="$(major_from_compiler g++)"
    if [[ -n "$gcc_major" && -n "$gxx_major" && "$gcc_major" -ge 12 && "$gxx_major" -ge 12 ]]; then
      echo "gcc;g++"
      return 0
    fi
  fi

  return 1
}

compiler_pair="$(select_compilers || true)"
if [[ -z "$compiler_pair" ]]; then
  echo "No GCC/G++ 12+ compiler pair found. Please install GCC 12 or newer." >&2
  exit 1
fi

CC="${compiler_pair%%;*}"
CXX="${compiler_pair##*;}"

echo "Using compilers: CC=${CC}, CXX=${CXX}"
echo "Building version: ${VERSION}"

build_deb=false
build_rpm=false

if command -v dpkg-deb >/dev/null 2>&1; then
  has_deb=true
else
  has_deb=false
fi

if command -v rpmbuild >/dev/null 2>&1; then
  has_rpm=true
else
  has_rpm=false
fi

case "$FORMAT" in
  auto)
    $has_deb && build_deb=true
    $has_rpm && build_rpm=true
    ;;
  deb)
    if ! $has_deb; then
      echo "dpkg-deb not found, cannot build .deb package." >&2
      exit 1
    fi
    build_deb=true
    ;;
  rpm)
    if ! $has_rpm; then
      echo "rpmbuild not found, cannot build .rpm package." >&2
      exit 1
    fi
    build_rpm=true
    ;;
  both)
    if ! $has_deb || ! $has_rpm; then
      echo "Both dpkg-deb and rpmbuild are required for --format both." >&2
      exit 1
    fi
    build_deb=true
    build_rpm=true
    ;;
esac

if ! $build_deb && ! $build_rpm; then
  echo "No supported packaging tools found for --format auto (need dpkg-deb and/or rpmbuild)." >&2
  exit 1
fi

cd "$REPO_ROOT"

cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX"

cmake --build build

cp build/rmp-eval .

if $build_deb; then
  echo "Building Debian package..."
  bash ./packaging/build_deb.sh "$VERSION"
fi

if $build_rpm; then
  echo "Building RPM package..."
  bash ./packaging/build_rpm.sh "$VERSION"
fi

echo "Done. Generated artifacts:"
ls -1 rmp-eval_"$VERSION"_*.deb rmp-eval_"$VERSION"_*.rpm 2>/dev/null || true
