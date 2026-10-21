#!/bin/bash
# verify action: installs the tools run-verification.sh uses.
set -e

sudo apt-get update
sudo apt-get install -y lynx html-xml-utils python3-pip jq bc

# Install muffet - comprehensive link and asset checker
wget -qO- https://github.com/raviqqe/muffet/releases/latest/download/muffet_linux_amd64.tar.gz | tar -xzf - -C /tmp
sudo mv /tmp/muffet /usr/local/bin/

muffet --version
