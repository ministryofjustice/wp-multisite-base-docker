#!/bin/bash

# test for a multisite table
MOJ_NETWORK_TABLE_NAME="sitemeta"
# define the config anchor
MOJ_WP_ANCHOR="/*multisite-network*/"
# define the config anchor
MOJ_WP_COOKIE_ANCHOR="/*cookie-domain*/"
# admin email address
MOJ_DEFAULT_SITE="default-site"
# colours
MOJ_COLOUR_RED="\033[0;31m"
MOJ_COLOUR_GREEN="\033[1;32m"
MOJ_COLOUR_YELLOW="\033[0;33m"
MOJ_COLOUR_END="\033[0m"

WPMS_LOCATION_WP_CONFIG="/bedrock/web/wp-config.php"
MOJ_CONFIG_FAILED=0
MOJ_COUNT_SUCCESS=0

function make_yellow() {
  echo -e "${MOJ_COLOUR_YELLOW}$1${MOJ_COLOUR_END}"
}
function countdown() {
  make_yellow "$1 ..."
  if [[ $1 == 0 ]]; then
    sleep 1 # slight breath before checking the network - MySQL needs to up and running
  else
    sleep 3
  fi
}

echo -e "\n\n- - - - - - -   ${MOJ_COLOUR_GREEN}W P   M U L T I S I T E   N E T W O R K   C O N F I G U R A T I O N${MOJ_COLOUR_END}   - - - - - - -\n\n"

# generate wp-config.php
# regenerate wp-config, remove it exists
rm -f "$WPMS_LOCATION_WP_CONFIG" || true
echo -e "Generating ${MOJ_COLOUR_YELLOW}wp-config.php${MOJ_COLOUR_END} here: ${MOJ_COLOUR_GREEN}$WPMS_LOCATION_WP_CONFIG${MOJ_COLOUR_END}"

{
  printf "<?php\n"
  printf "%s" "$MOJ_WP_COOKIE_ANCHOR\n"
  printf "\n\nrequire_once(dirname(__DIR__) . '/vendor/autoload.php');\n"
  printf "require_once(dirname(__DIR__) . '/config/application.php');\n\n"
  printf "%s" "$MOJ_WP_ANCHOR"
  printf "\n\nrequire_once(ABSPATH . 'wp-settings.php');\n"
} >>"$WPMS_LOCATION_WP_CONFIG" || MOJ_CONFIG_FAILED=1

if [[ "$MOJ_CONFIG_FAILED" == 0 ]]; then

  echo "Setting required constants..."

  wp config set BLOG_ID_CURRENT_SITE 1 --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
  wp config set SITE_ID_CURRENT_SITE 1 --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
  wp config set COOKIE_DOMAIN "\$_SERVER['HTTP_HOST'] ?? ''" --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
  wp config set DOMAIN_CURRENT_SITE "env('SERVER_NAME')" --raw --anchor="$MOJ_WP_COOKIE_ANCHOR" --placement='after' --allow-root
  wp config set SUBDOMAIN_INSTALL false --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
  wp config set MULTISITE true --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
  wp config set WP_ALLOW_MULTISITE true --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root

  MOJ_COUNT_SUCCESS=$((MOJ_COUNT_SUCCESS + 1))
fi

echo -e "Done... moving to configure network...\n"

countdown "Breathe in for 5"
countdown 4
countdown 3
countdown 2
countdown 1
countdown 0
echo -e "... checking network status...\n"

IS_NETWORK_INSTALLED=$(wp db query "SELECT IF( EXISTS(SELECT * FROM information_schema.tables WHERE table_name = '$(wp config get --global=table_prefix --allow-root)${MOJ_NETWORK_TABLE_NAME}'), 1, 0)" --allow-root --quiet)
IS_NETWORK_INSTALLED=$(sed "2q;d" <<<"$IS_NETWORK_INSTALLED")

# check, what did we get?
if [[ "$IS_NETWORK_INSTALLED" == "1" ]]; then
  echo -e "$MOJ_COLOUR_GREEN--- The network is already installed.$MOJ_COLOUR_END\n\n"
  MOJ_COUNT_SUCCESS=$((MOJ_COUNT_SUCCESS + 1))
else
  echo "Network is missing!"
  echo "Beginning network installation..."

  if wp core multisite-install --allow-root --title="MoJ D&T, Justice on the Web" \
    --admin_user="${WPMS_SA_USERNAME}" \
    --admin_email="${WPMS_SA_EMAIL}" \
    --admin_password="${WPMS_SA_PASSWORD}" \
    --skip-config \
    --skip-email \
    --quiet; then

    echo "The network has been installed."
    echo "Activate the default language: en_GB"

    wp site switch-language en_GB --allow-root

    echo "Network activating required plugins..."

    wp plugin --network --allow-root activate \
      wp-rewrite-media-to-s3 \
      wordpress-seo

    echo "Done :)"
    echo ""
    MOJ_COUNT_SUCCESS=$((MOJ_COUNT_SUCCESS + 1))

    # begin loading sites...
    echo "Moving to the /bedrock/import directory"

    if [[ -d "/bedrock/import" ]]; then
      # move to the import directory
      # shellcheck disable=SC2164
      cd /bedrock/import
      # do we have a zip file?
      if ls ./*.zip 1>/dev/null 2>&1; then
        echo "ZIP file was found!"

        # remove (with force) any directories inside import, keep all files
        rm -rf -- */

        # pick up the zip
        for i in *.zip; do
          echo "Unzipping..."
          unzip -q "$i" -d .
          rm -rf __MACOSX

          # only run the first .zip file found
          break
        done

        MOJ_DEFAULT_DIRECTORY="$MOJ_DEFAULT_SITE"
        MOJ_DIRECTORY_EXISTS=false

        echo "Checking zip file structure..."
        if [[ ! -d "$MOJ_DEFAULT_DIRECTORY" ]]; then
          # shellcheck disable=SC2012
          MOJ_ZIP_INNER_DIRECTORY_NAME=$(ls -d ./*/ | head -n 1)
          cd "$MOJ_ZIP_INNER_DIRECTORY_NAME" || exit 0

          if [[ ! -d "$MOJ_DEFAULT_DIRECTORY" ]]; then
            MOJ_DEFAULT_DIRECTORY="$MOJ_DEFAULT_SITE"
          else
            cd ../ && mv "$MOJ_ZIP_INNER_DIRECTORY_NAME"/* .
            rm -rf "$MOJ_ZIP_INNER_DIRECTORY_NAME"
            MOJ_DIRECTORY_EXISTS=true
          fi
        else
          MOJ_DIRECTORY_EXISTS=true
        fi

        echo "Done."

        MOJ_CURRENT_WORKING_DIR=$(pwd)

        if [[ "$MOJ_DIRECTORY_EXISTS" == true ]]; then
          # start the import
          echo "Beginning sites import..."

          # load users
          php load-users.php

          # remove users directory
          rm -rf ./users
          echo "Users done!..."

          # load taxonomies
          #php load-tax.php

          # remove taxonomies directory
          rm -rf ./taxonomies
          echo "Taxonomies done!..."

          # loop over directories
          for d in */; do
            echo ""
            php "${WPMS_GLOBAL_DIR}/import/load-site.php" "$d"
            echo -e "${MOJ_COLOUR_GREEN}Completed${MOJ_COLOUR_END}: $d"
          done

        else
          echo "$MOJ_DEFAULT_DIRECTORY does not exist here $MOJ_CURRENT_WORKING_DIR"
        fi
      else
        echo "Can't find a ZIP file.This script has a plugin that will import websites, please make sure there is a structured archive file available if you are expecting this functionality."
      fi
    else
      echo "The import directory does not exist. This script has a plugin that will import websites, please make sure there is a structured archive file available inside a /bedrock/import directory if you are expecting this functionality."
    fi
  fi

  if [[ "$MOJ_COUNT_SUCCESS" -ge 2 ]]; then
    echo -e "\n- - - - - - -  ${MOJ_COLOUR_GREEN}C O N G R A T U L A T I O N S${MOJ_COLOUR_END} - ${MOJ_COLOUR_GREEN}MULTISITE IS INSTALLED${MOJ_COLOUR_END}  - - - - - - -\n"
    echo -e "\n${MOJ_COLOUR_GREEN}USER${MOJ_COLOUR_END} : $WPMS_SA_USERNAME"
    echo -e "${MOJ_COLOUR_GREEN}LOGIN${MOJ_COLOUR_END}: ${WP_SITEURL}/wp-admin/\n\n"
  else
    echo -e "\n\n- - - - - - -  ${MOJ_COLOUR_RED}E R R O R${MOJ_COLOUR_END} - ${MOJ_COLOUR_RED}THE NETWORK WAS NOT INSTALLED${MOJ_COLOUR_END}  - - - - - - -\n\n"
  fi
fi
