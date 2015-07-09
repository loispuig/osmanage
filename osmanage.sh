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

		echo ""
		echo "---"

		echo "Name      : "$DATA_NAME
		echo "File      : "$DATA_FILE
		echo "PBF URL   : "$DATA_URL
		echo "Update URL: " $DATA_UPDATE_URL

		echo "---"

		if [ $PURGE ]; then
			echo "Purgin data files"
			rm -f $DATA_DIR/$DATA_FILE.osm.pbf $DATA_CHANGES $EXPIRED_TILES_LIST
			echo "Purging tiles"
			rm -rf $TILES_DIR/*
			echo "Purging database"
			sudo -u postgres psql -d gis --command "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres; GRANT ALL ON SCHEMA public TO public; COMMENT ON SCHEMA public IS 'standard public schema';"
			echo "Setup PostGIS on the PostgreSQL database"
			sudo -u postgres psql -d gis --command 'CREATE EXTENSION postgis;ALTER TABLE geometry_columns OWNER TO "www-data";ALTER TABLE spatial_ref_sys OWNER TO "www-data";'
		fi

		echo "---"

		if [ ! -e "$DATA_DIR/$DATA_FILE.osm.pbf" ]; then
			echo "OSM data file not found, starting download..."
			wget -O $DATA_DIR/$DATA_FILE.osm.pbf $DATA_URL
			
			echo "Importing $DATA_NAME to database"
			sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS --expire-tiles 0 --expire-output $EXPIRED_TILES_LIST $APPEND $DATA_DIR/$DATA_FILE.osm.pbf
		else
			echo "OSM data file found"
			
			echo "Downloading changes"
			osmupdate --base-url=$DATA_UPDATE_URL $DATA_DIR/$DATA_FILE.osm.pbf $DATA_CHANGES
			
			echo "Updating $DATA_NAME file"
			osmupdate --base-url=$DATA_UPDATE_URL $DATA_DIR/$DATA_FILE.osm.pbf $DATA_DIR/$DATA_FILE-new.osm.pbf
			
			# REMOVE OLD DATA FILE
			rm $DATA_DIR/$DATA_FILE.osm.pbf
			# RENAME NEW DATA FILE
			mv $DATA_DIR/$DATA_FILE-new.osm.pbf $DATA_DIR/$DATA_FILE.osm.pbf
			
			echo "Importing changes to database"
			sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS --expire-tiles 0 --expire-output $EXPIRED_TILES_LIST --append $DATA_CHANGES
		fi

		echo "Deleting expired tiles"
		cat $EXPIRED_TILES_LIST | render_expired --delete-from=0
		rm $EXPIRED_TILES_LIST

		i=$((i+1))
	else
		break;
	fi

	echo ""
done