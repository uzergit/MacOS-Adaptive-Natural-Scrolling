#!/bin/bash
# Builds the release assets: dist/install.sh (with a universal binary inside) and dist/uninstall.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/App.swift)
rm -rf build dist
mkdir -p build/payload dist

for arch in arm64 x86_64; do
  echo "Building $arch"
  swiftc -O -target "$arch-apple-macos13" Sources/*.swift -o "build/adaptive-scroll-$arch"
done
lipo -create build/adaptive-scroll-arm64 build/adaptive-scroll-x86_64 -output build/payload/adaptive-scroll
codesign --force --sign - build/payload/adaptive-scroll
install -m 755 scripts/uninstall.sh build/payload/uninstall.sh

tar -czf build/payload.tgz --uid 0 --gid 0 -C build/payload adaptive-scroll uninstall.sh
SHA=$(shasum -a 256 build/payload.tgz | cut -d' ' -f1)
/usr/bin/base64 -b 76 -i build/payload.tgz -o build/payload.b64

awk -v ver="$VERSION" -v sha="$SHA" -v pf="build/payload.b64" '
  $0 == "@PAYLOAD@" { while ((getline line < pf) > 0) print line; next }
  { gsub(/@VERSION@/, ver); gsub(/@PAYLOAD_SHA256@/, sha); print }
' scripts/install.sh > dist/install.sh
cp scripts/uninstall.sh dist/uninstall.sh
chmod 755 dist/*.sh

echo
echo "Version $VERSION"
ls -lh dist
shasum -a 256 dist/*
