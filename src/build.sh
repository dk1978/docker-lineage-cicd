#!/bin/bash

# Docker build script
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

repo_log="$LOGS_DIR/repo-$(date +%Y%m%d).log"

# cd to working directory
cd "$SRC_DIR"

for branch in ${BRANCH_NAME//,/ }; do
  if [ -n "$branch" ]; then
    vendor=lineage
    case "$branch" in
      cm-14.1*)
        vendor="cm"
        themuppets_branch="cm-14.1"
        android_version="7.1.2"
        patch_name="android_frameworks_base-N.patch"
        ;;
      lineage-15.1*)
        themuppets_branch="lineage-15.1"
        android_version="8.1"
        patch_name="android_frameworks_base-O.patch"
        ;;
      lineage-16.0*)
        themuppets_branch="lineage-16.0"
        android_version="9"
        patch_name="android_frameworks_base-P.patch"
        ;;
      lineage-17.1*)
        themuppets_branch="lineage-17.1"
        android_version="10"
        patch_name="android_frameworks_base-Q.patch"
        ;;
      *)
        echo ">> [$(date)] Building branch $branch is not (yet) suppported"
        exit 1
        ;;
      esac

    android_version_major=$(cut -d '.' -f 1 <<< $android_version)

    echo ">> [$(date)] Branch:  $branch"

    # Remove previous changes of vendor/cm, vendor/lineage and frameworks/base (if they exist)
    for path in "vendor/cm" "vendor/lineage" "frameworks/base"; do
      if [ -d "$path" ]; then
        cd "$path"
        git reset -q --hard
        git clean -q -fd
        cd "$SRC_DIR/$branch_dir"
      fi
    done

    if [ ! -d "vendor/$vendor" ]; then
      echo ">> [$(date)] Missing \"vendor/$vendor\", aborting"
      exit 1
    fi

    # Set up our overlay
    mkdir -p "vendor/$vendor/overlay/microg/"
    sed -i "1s;^;PRODUCT_PACKAGE_OVERLAYS := vendor/$vendor/overlay/microg\n;" "vendor/$vendor/config/common.mk"

    los_ver_major=$(sed -n -e 's/^\s*PRODUCT_VERSION_MAJOR = //p' "vendor/$vendor/config/common.mk")
    los_ver_minor=$(sed -n -e 's/^\s*PRODUCT_VERSION_MINOR = //p' "vendor/$vendor/config/common.mk")
    los_ver="$los_ver_major.$los_ver_minor"

    # If needed, apply the microG's signature spoofing patch
    if [ "$SIGNATURE_SPOOFING" = "yes" ] || [ "$SIGNATURE_SPOOFING" = "restricted" ]; then
      # Determine which patch should be applied to the current Android source tree
      cd frameworks/base
      if [ "$SIGNATURE_SPOOFING" = "yes" ]; then
        echo ">> [$(date)] Applying the standard signature spoofing patch ($patch_name) to frameworks/base"
        echo ">> [$(date)] WARNING: the standard signature spoofing patch introduces a security threat"
        patch --quiet -p1 -i "$MICROG_DIR/signature_spoofing_patches/$patch_name"
      else
        echo ">> [$(date)] Applying the restricted signature spoofing patch (based on $patch_name) to frameworks/base"
        sed 's/android:protectionLevel="dangerous"/android:protectionLevel="signature|privileged"/' "$MICROG_DIR/signature_spoofing_patches/$patch_name" | patch --quiet -p1
      fi
      git clean -q -f
      cd ../..

      # Override device-specific settings for the location providers
      mkdir -p "vendor/$vendor/overlay/microg/frameworks/base/core/res/res/values/"
      cp $MICROG_DIR/signature_spoofing_patches/frameworks_base_config.xml "vendor/$vendor/overlay/microg/frameworks/base/core/res/res/values/config.xml"
    fi

    # Set a custom updater URI if a OTA URL is provided
    echo ">> [$(date)] Adding OTA URL overlay (for custom URL $OTA_URL)"
    if ! [ -z "$OTA_URL" ]; then
      updater_url_overlay_dir="vendor/$vendor/overlay/microg/packages/apps/Updater/res/values/"
      mkdir -p "$updater_url_overlay_dir"

      if [ -n "$(grep updater_server_url packages/apps/Updater/res/values/strings.xml)" ]; then
        # "New" updater configuration: full URL (with placeholders {device}, {type} and {incr})
        sed "s|{name}|updater_server_url|g; s|{url}|$OTA_URL/v1/{device}/{type}/{incr}|g" $MICROG_DIR/packages_updater_strings.xml > "$updater_url_overlay_dir/strings.xml"
      elif [ -n "$(grep conf_update_server_url_def packages/apps/Updater/res/values/strings.xml)" ]; then
        # "Old" updater configuration: just the URL
        sed "s|{name}|conf_update_server_url_def|g; s|{url}|$OTA_URL|g" $MICROG_DIR/packages_updater_strings.xml > "$updater_url_overlay_dir/strings.xml"
      else
        echo ">> [$(date)] ERROR: no known Updater URL property found"
        exit 1
      fi
    fi

    # Add custom packages to be installed
    if ! [ -z "$CUSTOM_PACKAGES" ]; then
      echo ">> [$(date)] Adding custom packages ($CUSTOM_PACKAGES)"
      sed -i "1s;^;PRODUCT_PACKAGES += $CUSTOM_PACKAGES\n\n;" "vendor/$vendor/config/common.mk"
    fi

    if [ "$SIGN_BUILDS" = true ]; then
      echo ">> [$(date)] Adding keys path ($KEYS_DIR)"
      # Soong (Android 9+) complains if the signing keys are outside the build path
      ln -sf "$KEYS_DIR" user-keys
      if [ "$android_version_major" -lt "10" ]; then
        sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\nPRODUCT_EXTRA_RECOVERY_KEYS := user-keys/releasekey\n\n;" "vendor/$vendor/config/common.mk"
      fi

      if [ "$android_version_major" -ge "10" ]; then
        sed -i "1s;^;PRODUCT_DEFAULT_DEV_CERTIFICATE := user-keys/releasekey\nPRODUCT_OTA_PUBLIC_KEYS := user-keys/releasekey\n\n;" "vendor/$vendor/config/common.mk"
      fi
    fi

  fi
done
