./scripts/build.sh
mkdir -p dist

# Pre-sign the bundle deeply with hardened runtime before gon takes over
codesign --deep --force --options runtime \
  --sign "Developer ID Application: John Sterling" \
  ./apps/finicky/build/Finicky.app

export $(cat .env | xargs) && gon scripts/gon-config.json

