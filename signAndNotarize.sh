#!/bin/bash
#
# Nimbella CONFIDENTIAL
# ---------------------
#
#   2018 - present Nimbella Corp
#   All Rights Reserved.
#
# NOTICE:
#
# All information contained herein is, and remains the property of
# Nimbella Corp and its suppliers, if any.  The intellectual and technical
# concepts contained herein are proprietary to Nimbella Corp and its
# suppliers and may be covered by U.S. and Foreign Patents, patents
# in process, and are protected by trade secret or copyright law.
#
# Dissemination of this information or reproduction of this material
# is strictly forbidden unless prior written permission is obtained
# from Nimbella Corp.
#

#
# A script to sign and submit the build to Apple for notarization.
# The script makes the following assumptions:
# - 'pkgbuild' and 'altool' and are in your path.
# - a signing certificate is in your keychain for your Apple developer team id
# - a developer ID and Apple app-specific password also in your keychain (override the default via parameters)
#
# When this script is successful, the package is submitted to Apple for notarization
# and a tracking id is issued and logged to the console. Once Apple notarizes the
# application, it will notify the developer who submitted the request by email.
# A few minutes later, you can verify the package with this command:
# > spctl -a -vvv --type install <pkg name>
#

set -e

BASE=${1?Missing base location for package support files, metadata and scripts for example ./tmp}
PKG=${2?Missing package location for example ./dist/macos/nim-v0.1.8.pkg}
VERSION=${3?Missing version number for example 0.1.8}
TEAM_ID=${4?Missing team id for example FU8M787PV7}
DEV_ID=${5?Must specify an Apple id for example someone@example.com}
APPLE_PASSWORD=${6?App-specific password to keychain name required for Apple id}
ROOT="$BASE/darwin-x64/nim"
PRE_POST_SCRIPTS_LOC="$BASE/macos/scripts"
BUNDLE_ID=com.nimbella.cli
INSTALL_LOC=/usr/local/lib/nimbella-cli
SIGNING_CERT="Developer ID Installer: NIMBELLA CORPORATION ($TEAM_ID)"

pkgbuild \
  --root "$ROOT" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location "$INSTALL_LOC" \
  --scripts "$PRE_POST_SCRIPTS_LOC" \
  --sign "$SIGNING_CERT" \
  --timestamp=none \
  "$PKG"

xcrun altool \
  --notarize-app \
  --primary-bundle-id "$BUNDLE_ID" \
  --username "$DEV_ID" \
  --asc-provider "$TEAM_ID" \
  --password "$APPLE_PASSWORD" \
  --file "$PKG"
