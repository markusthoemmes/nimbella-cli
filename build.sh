#!/bin/bash
#
# DigitalOcean, LLC CONFIDENTIAL
# ------------------------------
#
#   2021 - present DigitalOcean, LLC
#   All Rights Reserved.
#
# NOTICE:
#
# All information contained herein is, and remains the property of
# DigitalOcean, LLC and its suppliers, if any.  The intellectual and technical
# concepts contained herein are proprietary to DigitalOcean, LLC and its
# suppliers and may be covered by U.S. and Foreign Patents, patents
# in process, and are protected by trade secret or copyright law.
#
# Dissemination of this information or reproduction of this material
# is strictly forbidden unless prior written permission is obtained
# from DigitalOcean, LLC.
#

# Builds the 'nim' CLI
#
# There are two build modes:
#   In "committed" mode, which is used for stable versions, the deployer is not separately built
#     and the CLI is built using its reference to a published version of the deployer.
#   In "repo" mode, which is used for everything else, the deployer repo must be present.  The
#     deployer is built and the package.json is updated so that the latest deployer is incorporated.
#
# With no flags, this script builds the deployer and CLI in "repo" mode, then installs it on your
# machine.
#
# Flags are mutually exclusive.
#
# Currently useful flags:
# With --pack the 'dist' area is built with the artifacts needed to support installs.
# With --no-install the build is done in "repo" mode but the final result is left as a tarball
#    and not installed.
# With --current, the --pack operation is performed and the result is then uploaded to
#    the DigitalOcean staging site: 
#          https://do-serverless-tools.nyc3.digitaloceanspaces.com/latest-nim/<various-artifacts>
#    Artifacts include self-contained tarballs, network install scripts for mac and linux, and
#    binary installers for mac and windows.
# With --stable it does the following
#    1.  Pre-checks the version numbering to assure that stable versions follow an orderly succession.
#    2.  The build itself is done in "committed" mode.
#    3.  Performs the --pack operation.
#    4.  Uploads to DigitalOcean similar to --current except that the target is
#          https://do-serverless-tools.nyc3.digitaloceanspaces.com/stable-nim-<version>/<various-artifacts>
#        The install scripts and installers (but not the tarballs) are duplicated in
#          https://do-serverless-tools.nyc3.digitaloceanspaces.com/nimbella-cli/...
#        so that you don't have to know the latest stable version in order to install.
#
# We used to sign the mac installer and had plans to sign the windows one.  It's not clear
# whether we will need to resume doing this because it is not clear that `nim` would be directly released
# to the public.  If `nim` is running as a plugin adjunct to `doctl` then it will simply ride on the 
# revised `doctl` install mechanism once we go public.
#
# Currently dormant flag (to be resurrected when we resume signing and notarizing):
# With --check-stable, there is no building and the mac installer in 'dist' is checked for successful notarization

# Change these variables on changes to the space we are uploading to or naming conventions within it
TARGET_SPACE=do-serverless-tools
VERSION_FILE=nim-cli-stable-version
LATEST_AREA=latest-nim
STABLE_AREA=stable-nim
DO_ENDPOINT=nyc3.digitaloceanspaces.com
SPACE_URL="https://$TARGET_SPACE.$DO_ENDPOINT"

# Change this variable when local setup for s3 CLI access changes
AWS="aws --profile do --endpoint https://$DO_ENDPOINT"

set -e

# Check for mandatory tools used in this script.
# Pulled from: https://stackoverflow.com/q/592620/
command_exists () {
    if ! command -v $1 &> /dev/null
    then
        echo "Missing dependency: $1 - Please install and re-run script"
        exit
    fi
}

# Backup a file that might be modified during the build
backup_file() {
  local dir=$1
  local file=$2
  echo "Backing up $dir/$file"
  cp "$dir/$file" "$dir/$file.bak"
}

# Backup files that might be modified during the build
backup_files() {
  if [ -n "$PUBLIC_CLI" ]; then
    echo "Backing up files in $PUBLIC_CLI"            
    backup_file "$PUBLIC_CLI" package.json
    backup_file "$PUBLIC_CLI" package-lock.json
    backup_file "$PUBLIC_CLI" README.md
  fi
  if [ -n "$DEPLOYER" ]; then
    echo "Backing up files in $DEPLOYER"            
    backup_file "$DEPLOYER" package.json
    backup_file "$DEPLOYER" package-lock.json
  fi
}

# Restore a file that might be modified during the build
restore_file() {
  local dir=$1
  local file=$2
  if [ -f "$dir/$file.bak" ]; then
    echo "Restoring $dir/$file"
    mv "$dir/$file.bak" "$dir/$file"
  fi
}

# Restore files that were modified during the build.
# To be executed via trap
restore_files() {
  if [ -n "$PUBLIC_CLI" ]; then
    echo "Restoring files in $PUBLIC_CLI"            
    restore_file "$PUBLIC_CLI" package.json
    restore_file "$PUBLIC_CLI" package-lock.json
    restore_file "$PUBLIC_CLI" README.md
  fi
  if [ -n "$DEPLOYER" ]; then
    echo "Restoring files in $DEPLOYER"            
    restore_file "$DEPLOYER" package.json
    restore_file "$DEPLOYER" package-lock.json
  fi
}

# Generate URLs for accessing uploaded artifacts.  There is one for linux and one for mac.
# They differ according to whether they are for "latest" or "stable."  It is assumed
# that the STABLE and VERSION variables have already been set.
generate_install_urls() {
  if [ -n "$STABLE" ]; then
    AREA="$STABLE_AREA-v$VERSION"
  else
    AREA="$LATEST_AREA"
  fi
  LINUX_URL="$SPACE_URL/$AREA/nim-v$VERSION/nim-v$VERSION-linux-x64.tar.gz"
  MAC_URL="$SPACE_URL/$AREA/nim-v$VERSION/nim-v$VERSION-darwin-x64.tar.gz"
}

# Upload a file to the target space.  Also sets a public-read ACL
# Warning: since this function uses aws s3 cp, which is "smart",
# this _could_ be called with dest=<prefix> instead of dest=<file>
# and get part way through the operation, leaving some mess.
# Please don't do that.  TODO figure out how to detect and prevent
# abuse.
upload_file() {
  local src="$1"
  local dest="$2"
  $AWS s3 cp "$src" "s3://$TARGET_SPACE/$dest"
  $AWS s3api put-object-acl --bucket "$TARGET_SPACE" --key "$dest" --acl public-read
}

# Copy a file within the target space.
copy_file() {
  local file="$1"
  local src_prefix="$2"
  local dest_prefix="$3"
  $AWS s3 cp "s3://$TARGET_SPACE/$src_prefix/$file" "s3://$TARGET_SPACE/$dest_prefix/$file"
  $AWS s3api put-object-acl --bucket "$TARGET_SPACE" --key "$dest_prefix/$file" --acl public-read
}

# Upload all the files in the 'dist' area.  Note we do not use the recursive feature
# of s3 cp for this because we have to set acls anyway and by doing it file by file
# we avoid anomalies stemming from the high level function's attempt to emulate
# cp's semantics for copying directories.
upload_dist() {
  local area="$1"
  FILES=$(cd "$PUBLIC_CLI/dist" && find * -type f)
  for file in $FILES; do
    SRC="$PUBLIC_CLI/dist/$file"
    DEST="$area/$file"
    upload_file "$SRC" "$DEST"
  done
}

# Check dependencies
for dependency in node npm pandoc jq
do
    command_exists $dependency
done

# Parse
if [ "$1" == "--pack" ]; then
  PKG=true
  NOINSTALL=true
elif [ "$1" == "--current" ]; then
	PKG=true
  NOINSTALL=true
	CURRENT=true
elif [ "$1" == "--stable" ]; then
	PKG=true
  NOINSTALL=true
  STABLE=true
elif [ "$1" == "--no-install" ]; then
  NOINSTALL=true
elif [ "$1" == "--check-stable" ]; then
	CHECKSTABLE=true
elif [ -n "$1" ]; then
  echo "Illegal argument '$1'"
  exit 1
fi

# Further dependency check if packing
if [ -n "$PKG" ]; then
  for dependency in 7z makensis; do
    command_exists $dependency
  done
fi

# Orient
SELFDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT=$(dirname $SELFDIR)

if [ -z "$MAINDIR" ]; then
  MAINDIR="$PARENT/main"
  if ! [ -d "$MAINDIR" ]; then
    echo "The main repo must be a peer of nimcli or its location specified in the environment"
    exit 1
  fi
fi

if [ -z "$PUBLIC_CLI" ]; then
  PUBLIC_CLI="$PARENT/nimbella-cli"
  if ! [ -d "$PUBLIC_CLI" ]; then
    echo "The public nimbella-cli repo must be a peer of nimcli or its location specified in the environment"
    exit 1
  fi
fi

if [ -z "$STABLE" ] && [ -z "$DEPLOYER" ]; then
  DEPLOYER="$PARENT/nimbella-deployer"
  if ! [ -d "$DEPLOYER" ]; then
    echo "Except for stable builds, the public nimbella-deployer repo must be a peer of nimcli or its location specified in the environment"
    exit 1
  fi
fi

# The build takes place in the public repo
cd $PUBLIC_CLI

DIRTY=$(git status --porcelain)

# Check prereqs for --stable
if [ -n "$STABLE" ]; then
    if [ -n "$DIRTY" ]; then
        echo "The nimbella-cli repo is not fully committed: a stable version cannot be declared"
        exit 1
    fi
    LAST_VERSION=$(curl -s "$SPACE_URL/$VERSION_FILE")
    NEW_VERSION=$(jq -r .version < package.json)
    if [ "$LAST_VERSION" == "$NEW_VERSION" ]; then
        echo "The nim CLI version number was not changed: a new stable version cannot be declared"
        exit 1
    fi
    echo "This build will use only committed code (including published deployer)."
fi

# Test for valid s3 CLI setup (will exit on failure due to set -e)
if [ -n "$STABLE" ] || [ -n "$CURRENT" ]; then
  echo "Testing that there is a valid s3 CLI setup"
  $AWS s3 ls "s3://$TARGET_SPACE/$VERSION_FILE" > /dev/null
fi

# Ensure a somewhat clean start.  Also back up any backup files that might be modified.
rm -fr $PUBLIC_CLI/*gz $PUBLIC_CLI/dist $PUBLIC_CLI/tmp
echo "Backing up committed files that might be modified"
backup_files
trap restore_files EXIT

# If we need to build the deployer, do so.
# Note: we do not use 'npm link' here.  That works fine during
# development / debugging but the oclif packager will rebuild
# from scratch and either bypass the symlinks or be confused
# by them.
if [ -z "$STABLE" ]; then
  echo "Building the deployer."
	cd $DEPLOYER
	npm install
	npm pack
	# Move the deployer tarball into the CLI repo, then install to
	# force its use instead of the npm reference to the deployer.
	mv nimb*.tgz $PUBLIC_CLI
	cd $PUBLIC_CLI
	echo "Installing the deployer for use in this build"
	npm install nimb*.tgz
fi

# Store version info
echo "Generating version and build info for incorporation."
HASH=$(git rev-parse HEAD)
if [ -n "$DIRTY" ]; then
    DIRTY="++"
fi
BUILDINFO=${HASH:0:8}${DIRTY}
VERSION=$(jq -r .version package.json)
FULLVERSION="$VERSION ($BUILDINFO)"
echo '{ "version": "'$FULLVERSION'" }' | jq . > version.json

# Ensure the working copy doesn't include the husky install.
echo "Ensuring the working copy doesn't include husky."
sed -i '' -e 's/&& husky install//' package.json

# Generate the license-notices.md file.  Note: to avoid unnecessary entries
# this step requires a clean production install.  We do a full install later.
# Failures of this step are terminal when building a stable version but are
# considered "warnings" otherwise.
rm -fr node_modules package-lock.json
echo "Doing lightweight install for license step"
npm install --production --no-optional --ignore-scripts
if [ -z "$STABLE" ]; then
  set +e
fi
echo "Generating licenses"
node $SELFDIR/license-notices.js > thirdparty-licenses.md
# Error check here will only happen in the non-stable case
if [ $? -ne 0 ]; then
    echo "!!!"
    echo "!!! License issues must be resolved in time for the next stable version"
    echo "!!!"
fi
set -e

# Build the HTML forms of the LICENSE, and changes
cp $SELFDIR/doc/change-header /tmp/changes.md
tail -n +2 < $SELFDIR/doc/changes.md >> /tmp/changes.md
pandoc -o changes.html -f markdown -s -t html < /tmp/changes.md
cp $SELFDIR/doc/license-header /tmp/license.md
tail -n +4 < $SELFDIR/LICENSE >> /tmp/license.md
pandoc -o license.html -f markdown-smart -s -H $SELFDIR/doc/tracker.html --html-q-tags -t html < /tmp/license.md
pandoc -o thirdparty-licenses.html -f markdown_strict -t html < thirdparty-licenses.md

# Copy in the oclif-dev patch.  This must be present when
# the full install is done, although it is only necessary when
# building a stable release.  It is harmless otherwise.
cp -r $SELFDIR/patches .

# Full install
echo "Doing full install"
npm install --no-optional

# Copy in the latestproductionProjects.json & sensitiveNamespaces.json into the deployer library
cp $MAINDIR/config/productionProjects.json node_modules/@nimbella/nimbella-deployer
cp $SELFDIR/sensitiveNamespaces.json node_modules/@nimbella/nimbella-deployer

# Build and pack
echo "Making tarball for npm install"
npm pack
mv nimbella-nimbella-cli-*.tgz nimbella-cli.tgz

# Unless told not to, do a "global" (to this machine) install of the result
if [ -z "$NOINSTALL" ]; then
    echo "Doing local install"
    npm install -g nimbella-cli.tgz
fi

# Optionally package
if [ -n "$PKG" ]; then
	  echo "Entering the packaging phase"

    # Rename READMEs so the customer gets an appropriate one (not our internal one)
    cp $SELFDIR/userREADME.md README.md

    # Create the standalone tarballs
    npx oclif-dev pack -t linux-x64,darwin-x64

    # Generate needed URLs for install scripts
    generate_install_urls

    # Generate the install scripts in 'dist'.
    sed -e 's+URL=+URL='$LINUX_URL'+' < $SELFDIR/nim-install-linux.sh > dist/nim-install-linux.sh
    sed -e 's+URL=+URL='$MAC_URL'+' < $SELFDIR/nim-install-mac.sh > dist/nim-install-mac.sh

    # Add licenses
    cp license.html thirdparty-licenses.html dist

    # Create installers for macos and win (keep x64 only) and provide consistent naming
    npx oclif-dev pack:macos
    MACOS=dist/macos/*.pkg
    mv $MACOS dist/macos/nim.pkg
    npx oclif-dev pack:win
    rm -f dist/win/*x86*
    WIN=dist/win/*x64.exe
    mv $WIN dist/win/nim-x64.exe
fi

# Optionally upload to the latest-nim staging area
if [ -n "$CURRENT" ]; then
  echo "Uploading the contents of 'dist' to 's3://$TARGET_SPACE/$LATEST_AREA'"
  upload_dist "$LATEST_AREA"
fi  

# Optionally make stable version
if [ -n "$STABLE" ]; then
  VERSIONED_AREA="$STABLE_AREA-v$VERSION"
  # Store the entire dist folder
  echo "Uploading the contents of 'dist' to 's3://$TARGET_SPACE/$VERSIONED_AREA'"
  upload_dist "$VERSIONED_AREA"
  # Also place install scripts and installers in an unversioned location.
  echo "Duplicating files in the unversioned stable area"
  # Scripts are tiny.  Just do a second upload. Note the full dest paths are 
  # required by upload_file.
  upload_file "dist/nim-install-linux.sh" "$STABLE_AREA/nim-install-linux.sh" 
  upload_file "dist/nim-install-mac.sh" "$STABLE_AREA/nim-install-mac.sh"
  # Installers are large.  Copy within bucket
  copy_file "macos/nim.pkg" "$VERSIONED_AREA" "$STABLE_AREA"
  copy_file "win/nim-x64.exe" "$VERSIONED_AREA" "$STABLE_AREA"
  # Set the version indicator
  echo "$VERSION" > "$VERSION_FILE"
  upload_file "$VERSION_FILE" "$VERSION_FILE"
  rm "$VERSION_FILE"
fi
