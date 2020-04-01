#!/bin/bash

# test for a multisite table
MOJ_NETWORK_TABLE_NAME='sitemeta'
# define the anchor
MOJ_WP_ANCHOR="/*multisite-network*/"
# where is wp-config
MOJ_LOCATION_WP_CONFIG="/bedrock/web/wp-config.php"
# where is ims-global
MOJ_MS_GLOBAL_DIR="/bedrock/web/app/ms-global"
# admin email address
MOJ_S_ADMIN_USERNAME="ms-admin-team"
# admin email address
MOJ_DEFAULT_SITE="default-site"
# colours
MOJ_COLOUR_GREEN="\033[1;32m"
MOJ_COLOUR_END="\033[0m"

# generate wp-config.php
# check if the file exists...
if [[ ! -f "$MOJ_LOCATION_WP_CONFIG" ]]
then
	echo "Starting with wp-config generation."

	touch ${MOJ_LOCATION_WP_CONFIG}

	{
	  printf "<?php\n"
    printf "\nrequire_once(dirname(__DIR__) . '/vendor/autoload.php');\n"
    printf "require_once(dirname(__DIR__) . '/config/application.php');\n\n"
    printf "%s" "$MOJ_WP_ANCHOR"
    printf "\n\nrequire_once(ABSPATH . 'wp-settings.php');\n"
	} >> ${MOJ_LOCATION_WP_CONFIG}

	echo "Done... configuring network..."
fi

IS_NETWORK_INSTALLED=$(wp db query "SELECT IF( EXISTS(SELECT * FROM information_schema.tables WHERE table_name = '$DB_PREFIX$MOJ_NETWORK_TABLE_NAME'), 1, 0)" --allow-root --quiet)
IS_NETWORK_INSTALLED=$(sed "2q;d" <<< "$IS_NETWORK_INSTALLED")

# check, what did we get?
if [[ "$IS_NETWORK_INSTALLED" = "1" ]]; then
	echo "The network is already installed."
else
	echo "Network is missing!"
	echo "Beginning network installation..."

	wp core multisite-install --allow-root --title="MoJ Intranet" \
	 --admin_user="${MOJ_S_ADMIN_USERNAME}" \
	 --admin_email="${MOJ_ADMIN_EMAIL}" \
	 --admin_password="${NETWORK_INIT_SA_PASSWORD}" \
	 --skip-config \
	 --skip-email \
	 --quiet

	echo "The network has been installed."
	echo "Setting required constants..."

	wp config set BLOG_ID_CURRENT_SITE 1 --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
	wp config set SITE_ID_CURRENT_SITE 1 --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
	wp config set DOMAIN_CURRENT_SITE "env('SERVER_NAME')" --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
	wp config set SUBDOMAIN_INSTALL false --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
	wp config set MULTISITE true --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root
	wp config set WP_ALLOW_MULTISITE true --raw --anchor="$MOJ_WP_ANCHOR" --placement='after' --allow-root

	echo "Activate the default language: en_GB"

	wp site switch-language en_GB --allow-root

	echo "Activating plugins..."

	wp plugin activate \
		advanced-custom-fields-pro \
		classic-editor \
		fast-user-switching \
		google-analytics-dashboard-for-wp \
		wp-rewrite-media-to-s3 \
		wordpress-seo \
		--network  --allow-root

	echo "Done :)"
	echo ""

	# begin loading sites...
  echo "Moving to the /bedrock/import directory"
	# move to the import directory
	cd /bedrock/import/ || echo "The import directory did not exist" && exit 0

	# do we have a zip file?
	if ls ./*.zip 1> /dev/null 2>&1; then
		echo "ZIP file was found!"
	else
		echo "Can't find a ZIP file. Please make sure there is a structured archive file available."
		exit 0
	fi

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
	if [[ ! -d "$MOJ_DEFAULT_DIRECTORY" ]]
	then
		# shellcheck disable=SC2012
		MOJ_ZIP_INNER_DIRECTORY_NAME=$(ls -d ./*/|head -n 1)
		cd "$MOJ_ZIP_INNER_DIRECTORY_NAME" || exit 0

		if [[ ! -d "$MOJ_DEFAULT_DIRECTORY" ]]
		then
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

	if [[ "$MOJ_DIRECTORY_EXISTS" = true ]]
	then
		# start the import
		echo "Beginning sites import..."

		# load users
		#php load-users.php

		# remove users directory
		#rm -rf ./users
		echo "Users done!..."

		# load taxonomies
		#php load-tax.php

		# remove taxonomies directory
		#rm -rf ./taxonomies
		echo "Taxonomies done!..."

		# loop over directories
		for d in */; do
			echo ""
			php "${MOJ_MS_GLOBAL_DIR}/import/load-site.php" "$d"
			echo -e "${MOJ_COLOUR_GREEN}Completed${MOJ_COLOUR_END}: $d"
		done

	else
		echo "$MOJ_HQ_DIRECTORY does not exist here $MOJ_CURRENT_WORKING_DIR"
	fi

	echo ""
	MOJ_ADMIN_LOGIN_SCREEN="/wp-admin/"
	echo -e "- - - - - - -  ${MOJ_COLOUR_GREEN}C O N G R A T U L A T I O N S${MOJ_COLOUR_END} - ${MOJ_COLOUR_GREEN}Multisite HAS BEEN INSTALLED${MOJ_COLOUR_END} - - - - - - -"
	echo ""
	echo "USER : $MOJ_S_ADMIN_USERNAME"
	echo "LOGIN: $WP_SITEURL$MOJ_ADMIN_LOGIN_SCREEN"
	echo ""
fi
