#!/bin/bash
# build action: installs the gems and builds
# the preview site into _site.
#
# Run in the PR's checkout, with the theme in _theme. Needs BASEURL, e.g.
# /pr-12. If apply-fork-overrides.sh wrote _config_security.yml, it is
# stacked on _config.yml.
set -e

if [ -z "$BASEURL" ]; then
  echo "BASEURL is not set" >&2
  exit 1
fi
if [ ! -d _theme ] || [ -z "$(ls -A _theme)" ]; then
  echo "_theme is missing or empty" >&2
  exit 1
fi

export PATH=$PATH:~/.local/share/gem/ruby/3.1.0/bin

# No gem cache: this job runs PR code in main's cache scope, so it
# neither restores nor saves one
bundle install

echo "🔨 Building Jekyll site..."
CONFIG_FLAG=""
if [ -f _config_security.yml ]; then
  CONFIG_FLAG="--config _config.yml,_config_security.yml"
  echo "🔒 Using security config override"
fi
# shellcheck disable=SC2086  # CONFIG_FLAG is empty or two words
bundle exec jekyll build --baseurl "$BASEURL" --future $CONFIG_FLAG
echo "✅ Site built successfully"
