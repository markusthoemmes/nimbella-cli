#!/bin/bash

# This script installs current linux self-contained tarball on a target system
# It should be run under sudo as in
#   curl https://<URL-of-this-script> | sudo bash

# URL of the tarball to install (generated during build)
URL=

# Download and unpack the tarball
set -e
echo Downloading the standalone 'nim' distribution for Linux from $URL
NIM_TMP="$(mktemp -d)"
cd $NIM_TMP
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

rm -r $NIM_TMP
echo Installation complete
