#!/bin/bash

set -e
clear

#*************************************************************************
#*************************************************************************
JQ_BIN=/usr/bin/jq
OSMOSIS_BIN=osmosis
OSM2PGSQL_BIN=/usr/local/share/osm2pgsql/osm2pgsql
OSM2PGSQL_OPTIONS="--slim -d gis -C 3000 --number-processes 4"
#OSM2PGSQL_OPTIONS="--flat-nodes /path/to/flatnodes --hstore"

TILES_DIR=/var/lib/mod_tile/default
PBF=/usr/local/share/maps/planet/aquitaine.osm.pbf


BASE_DIR=/usr/local/share/maps/planet
LOG_DIR=/var/log/osmupdate/

CHANGE_FILE=$BASE_DIR/changes.osc.gz

UPDATELOG=$LOG_DIR/osmupdate.log
OSM2PGSQLLOG=$LOG_DIR/osm2pgsql.log

#********

#mkdir $WORKOSM_DIR

 #   $OSMOSIS_BIN --read-replication-interval-init workingDirectory=$WORKOSM_DIR 1>&2 2> "$OSMOSISLOG"
 #   wget "http://osm.personalwerk.de/replicate-sequences/?"$1"T00:00:00Z" -O $WORKOSM_DIR/state.txt

#osmupdate --base-url=download.geofabrik.de/europe/france/aquitaine-updates aquitaine-latest.osm.pbf aquitaine-latest.$

JSONFILE=osmdata.json

i="0"
while true; do
    DATANAME=`$JQ_BIN -r ".[$i].name" $JSONFILE`
    DATAPBFURL=`$JQ_BIN -r ".[$i].pbf" $JSONFILE`
    DATAUPDATEURL=`$JQ_BIN -r ".[$i].changes" $JSONFILE`

    if [ $DATANAME != "null" ]; then

        # UPDATE
#        osmupdate --base-url=$DATAUPDATEURL 

        DATAFILE=`basename $DATAPBFURL | cut -d'.' -f1`
        DATACHANGES=$BASE_DIR/$DATAFILE-changes.osc

        echo ""
        echo "---"

        echo "Name: "$DATANAME
        echo "File: "$DATAFILE
        echo "PBF URL: "$DATAPBFURL
        echo "Update URL: " $DATAUPDATEURL

        echo "---"

        if [ ! -e "$BASE_DIR/$DATAFILE.osm.pbf" ]; then
            echo "File not found, starting download..."
            wget -O $BASE_DIR/$DATAFILE.osm.pbf $DATAPBFURL
            echo "Importing $DATANAME to database"
            sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS $BASE_DIR/$DATAFILE.osm.pbf
        else
            echo "File already exists, starting update..."
            echo "Downloading changeset"
            osmupdate --base-url=$DATAUPDATEURL $BASE_DIR/$DATAFILE.osm.pbf $DATACHANGES
            echo "Updating $DATANAME file"
            osmupdate --base-url=$DATAUPDATEURL $BASE_DIR/$DATAFILE.osm.pbf $BASE_DIR/$DATAFILE-new.osm.pbf
            echo "Importing changes to database"
            sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS $DATACHANGES
            echo "Deleting old tiles"
            rm -Rf $TILES_DIR/*
        fi

#        echo "Recording $DATANAME to database"
#        sudo -u www-data $OSM2PGSQL_BIN $OSM2PGSQL_OPTIONS $DATACHANGES

        i=$((i+1))

    else
        break;
    fi

    echo ""
done