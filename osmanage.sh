#!/bin/bash

set -e
clear

while getopts pp: option
do
	case "${option}"
	in
	p) PURGE=true;;
	esac
done

GREEN="\\033[1;32m"
NORMAL="\\033[0;39m"
RED="\\033[1;31m"
ROSE="\\033[1;35m"
BLUE="\\033[1;34m"
WHITE="\\033[0;02m"
BRIGHTWHITE="\\033[1;08m"
YELLOW="\\033[1;33m"
CYAN="\\033[1;36m"

#*************************************************************************

OSM2PGSQL_BIN=/usr/local/share/osm2pgsql/osm2pgsql
OSM2PGSQL_OPTIONS="--cache 3000 --database gis --slim --number-processes 4"

JSON=osmdata.json

TILES_DIR=/var/lib/mod_tile/default

DATA_DIR=/usr/local/share/maps/planet

#*************************************************************************

i="0"
while true; do
	DATA_NAME=`jq -r ".[$i].name" $JSON`
	DATA_URL=`jq -r ".[$i].pbf" $JSON`
	DATA_UPDATE_URL=`jq -r ".[$i].changes" $JSON`

	if [ $DATA_NAME != "null" ]; then

		DATA_FILE=`basename $DATA_URL | cut -d'.' -f1`
		DATA_CHANGES=$DATA_DIR/$DATA_FILE-changes.osc
		EXPIRED_TILES_LIST=$TILES_DIR/../$DATA_FILE-expired-tiles.list

		echo ""$GREEN
		echo "---"

		echo "Name      : "$DATA_NAME
		echo "File      : "$DATA_FILE
		echo "PBF URL   : "$DATA_URL
		echo "Update URL: "$DATA_UPDATE_URL

		echo "---"$NORMAL

		if [ $PURGE ]; then
			echo "Purging data files"
			rm -f $DATA_DIR/$DATA_FILE.osm.pbf $DATA_CHANGES $EXPIRED_TILES_LIST
			echo "Purging tiles"
			rm -rf $TILES_DIR/*
			echo "Purging database"
			sudo -u postgres psql -d gis --command "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public; COMMENT ON SCHEMA public IS 'standard public schema';"
			echo "Setup PostGIS on the PostgreSQL database"
			sudo -u postgres psql -d gis --command 'CREATE EXTENSION postgis;ALTER TABLE geometry_columns OWNER TO "www-data";ALTER TABLE spatial_ref_sys OWNER TO "www-data";'
			echo $GREEN"---"$NORMAL
		fi

		if [ ! -e "$DATA_DIR/$DATA_FILE.osm.pbf" ]; then
			echo $GREEN"OSM data file not found, starting download..."
			wget -O $DATA_DIR/$DATA_FILE.osm.pbf $DATA_URL
			
			echo $GREEN"Importing $DATA_NAME to database"$NORMAL
			sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS --expire-tiles 2 --expire-output $EXPIRED_TILES_LIST $APPEND $DATA_DIR/$DATA_FILE.osm.pbf
		else
			echo $GREEN"OSM data file found"$NORMAL
			
			echo $GREEN"Downloading changes"$NORMAL
			osmupdate --base-url=$DATA_UPDATE_URL $DATA_DIR/$DATA_FILE.osm.pbf $DATA_CHANGES
			
			echo $GREEN"Updating $DATA_NAME file"$NORMAL
			#osmupdate --base-url=$DATA_UPDATE_URL $DATA_DIR/$DATA_FILE.osm.pbf $DATA_DIR/$DATA_FILE-new.osm.pbf
			wget -O $DATA_DIR/$DATA_FILE.osm.pbf $DATA_URL
			
			echo $GREEN"Importing changes to database"$NORMAL
			echo $GREEN"$OSM2PGSQL_OPTIONS --expire-tiles 2 --expire-output $EXPIRED_TILES_LIST --append $DATA_CHANGES"$NORMAL
			#sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS --expire-tiles 2 --expire-output $EXPIRED_TILES_LIST --append $DATA_CHANGES
		fi

		echo $GREEN"Deleting expired tiles"$NORMAL
		#cat $EXPIRED_TILES_LIST | render_expired --delete-from=0
		cat $EXPIRED_TILES_LIST
#		rm $EXPIRED_TILES_LIST

		i=$((i+1))
	else
		break;
	fi

	echo $GREEN""$NORMAL
done