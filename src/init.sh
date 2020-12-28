#!/bin/bash

# Docker init script
# Copyright (c) 2017 Julian Xhokaxhiu
# Copyright (C) 2017-2018 Nicola Corna <nicola@corna.info>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

export SIGN_BUILDS=false
export SRC_DIR=/data/lineageOS
export MICROG_DIR=/data/microG/src
export BRANCH_NAME=lineage-17.1
export DEVICE_LIST=FP3
export SIGNATURE_SPOOFING=restricted
export CUSTOM_PACKAGES='GmsCore GsfProxy FakeStore MozillaNlpBackend NominatimNlpBackend com.google.android.maps.jar FDroid FDroidPrivilegedExtension'

export RELEASE_TYPE=userdebug
export ZIP_DIR=/tmp/microG/out
export LOGS_DIR=/tmp/microG/logs
export INCLUDE_PROPRIETARY=true

mkdir -p $ZIP_DIR
mkdir -p $LOGS_DIR

if [ "$SIGN_BUILDS" = true ]; then
  if [ -z "$(ls -A "$KEYS_DIR")" ]; then
    echo ">> [$(date)] SIGN_BUILDS = true but empty \$KEYS_DIR, generating new keys"
    for c in releasekey platform shared media networkstack; do
      echo ">> [$(date)]  Generating $c..."
      $MICROG_DIR/make_key "$KEYS_DIR/$c" "$KEYS_SUBJECT" <<< '' &> /dev/null
    done
  else
    for c in releasekey platform shared media networkstack; do
      for e in pk8 x509.pem; do
        if [ ! -f "$KEYS_DIR/$c.$e" ]; then
          echo ">> [$(date)] SIGN_BUILDS = true and not empty \$KEYS_DIR, but \"\$KEYS_DIR/$c.$e\" is missing"
          exit 1
        fi
      done
    done
  fi

  for c in cyngn{-priv,}-app testkey; do
    for e in pk8 x509.pem; do
      ln -s releasekey.$e "$KEYS_DIR/$c.$e" 2> /dev/null
    done
  done
fi

$MICROG_DIR/build.sh
