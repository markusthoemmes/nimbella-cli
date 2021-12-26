#!/bin/bash

# This script installs current macos self-contained tarball on a target system
# Assuming that /usr/local/lib and /usr/local/bin are writeable (as they usually are
# on a mac) executing with 'sudo' is unnecessary and should be avoided.

# URL of the tarball to install (generated during build)
URL=

# Download and unpack the tarball
set -e
echo Downloading the standalone 'nim' distribution for MacOs from $URL
cd /tmp
curl -o nim-install.tgz $URL
tar xzf nim-install.tgz

# Swap in the new version
echo Removing old installation, if any, and swapping in the new
rm -fr /usr/local/lib/nimbella-cli
mv nim /usr/local/lib/nimbella-cli

# Swap in the new symlink
echo Removing old symlink, if any, from /usr/local/bin and establishing the new
rm -f /usr/local/bin/nim
ln -s /usr/local/lib/nimbella-cli/bin/nim /usr/local/bin/

rm -fr nim nim-install.tgz
echo Installation complete
