#!/bin/bash
# verify action: installs the tools run-verification.sh uses.
set -e

sudo apt-get update
sudo apt-get install -y lynx html-xml-utils python3-pip jq bc

# Install muffet at pinned version with checksum verification.
# .github/workflows/update-muffet.yml opens a PR to update these when
# muffet releases
MUFFET_VERSION="v2.11.6"
MUFFET_SHA256="f190c7cf7b1c002120f1ac0164e4c50a35b5d9129799520e393bcd23820ab87a"
MUFFET_URL="https://github.com/raviqqe/muffet/releases/download/${MUFFET_VERSION}/muffet_linux_amd64.tar.gz"

cd "$RUNNER_TEMP"
wget -q -O muffet.tar.gz "$MUFFET_URL"
echo "${MUFFET_SHA256}  muffet.tar.gz" | sha256sum --check --strict
tar -xzf muffet.tar.gz muffet
sudo mv muffet /usr/local/bin/
rm muffet.tar.gz

muffet --version
