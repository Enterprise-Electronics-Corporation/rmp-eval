#!/usr/bin/env bash
set -euxo pipefail

# If no version provided, extract from version.h
if [ "$#" -eq 0 ]; then
  SCRIPT_DIR="$(dirname "$0")"
  VERSION=$("${SCRIPT_DIR}/../scripts/get_version.sh")
  echo "Using version from version.h: ${VERSION}"
elif [ "$#" -eq 1 ]; then
  VERSION="$1"
else
  echo "Usage: $0 [version]" >&2
  exit 1
fi

if [ ! -f rmp-eval ]; then
  echo "rmp-eval binary not found. Build it first." >&2
  exit 1
fi

ARCH=$(rpm --eval '%{_arch}')
BUILD_DIR="build/rpmbuild"
SPECS_DIR="$BUILD_DIR/SPECS"
SOURCES_DIR="$BUILD_DIR/SOURCES"

rm -rf "$BUILD_DIR"
mkdir -p "$SPECS_DIR" "$SOURCES_DIR"

install -m 0755 rmp-eval "$SOURCES_DIR/rmp-eval"

cat <<SPEC > "$SPECS_DIR/rmp-eval.spec"
Name:           rmp-eval
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Utility to evaluate Linux latency and real-time capabilities
License:        MIT
BuildArch:      %{_arch}
Source0:        rmp-eval

%description
A simple utility to evaluate latencies on a Linux system and determine
real-time capabilities.

%prep

%build

%install
mkdir -p %{buildroot}/usr/bin
install -m 0755 %{SOURCE0} %{buildroot}/usr/bin/rmp-eval

%files
/usr/bin/rmp-eval

%changelog
* Mon May 11 2026 Micro Rokoku Maintainers <noreply@example.com> - ${VERSION}-1
- Automated RPM build
SPEC

rpmbuild -bb "$SPECS_DIR/rmp-eval.spec" --define "_topdir $(pwd)/$BUILD_DIR"

RPM_OUTPUT=$(find "$BUILD_DIR/RPMS" -type f -name '*.rpm' | head -n1)
if [ -z "$RPM_OUTPUT" ]; then
  echo "RPM package was not produced." >&2
  exit 1
fi

FINAL_NAME="rmp-eval_${VERSION}_${ARCH}.rpm"
cp "$RPM_OUTPUT" "$FINAL_NAME"
echo "Built RPM artifact: $FINAL_NAME"
