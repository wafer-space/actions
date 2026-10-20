#!/bin/bash
# build action: before building a fork PR,
# replace everything that can run code during the build with trusted
# versions:
# - _plugins/ (Ruby code Jekyll runs), including files the fork had
#   before this PR, which don't appear in the PR diff
# - Gemfile (gems Bundler installs and loads); any Gemfile.lock is
#   removed, as main has none
# - .bundle/ (Bundler config could point BUNDLE_GEMFILE elsewhere)
# and write a config to stack on _config.yml that stops it redirecting
# plugins_dir, source or destination.
#
# The build job has no secrets, so this is defence in depth: it stops a
# fork PR running its own code even there, e.g. to tamper with the build
# or the Actions cache.
#
# Usage: apply-fork-overrides.sh TRUSTED_DIR
# Run in the PR's checkout. TRUSTED_DIR is a checkout of main.
set -e

TRUSTED_DIR="$1"
if [ -z "$TRUSTED_DIR" ] || [ ! -f "$TRUSTED_DIR/_config.yml" ]; then
  echo "Usage: $0 TRUSTED_DIR (a checkout of main)" >&2
  exit 1
fi

echo "🔒 Applying security overrides for fork PR..."

cat > _config_security.yml << 'SECURITY_EOF'
# Security overrides for fork PR builds - do not modify
plugins_dir: _plugins
source: .
destination: _site
SECURITY_EOF

rm -rf _plugins/
cp -r "$TRUSTED_DIR/_plugins" _plugins
echo "✅ Replaced _plugins/ with trusted version from main"

# Gemfile.lock is gitignored, so main has none. A fork could still
# commit one to pin gem versions or sources, so remove it.
cp "$TRUSTED_DIR/Gemfile" .
rm -f Gemfile.lock
echo "✅ Using trusted Gemfile from main"

rm -rf .bundle
echo "✅ Removed .bundle/"
