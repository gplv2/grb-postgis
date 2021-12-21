#!/bin/bash -e

set -o allexport
source /tmp/configs/variables
set +o allexport

OGRIDFILE=ogr2osm.id

DBUSER=grb-data
DBDATA=grb_api

cd /usr/local/src/grb

# This script has been converted from the beta development site

# We need to keep track of the OGRIDFILE id as it allows us to incrementally process files instead of making a huge one while still keeping osm id unique across files
# default value is zero but the file does need to exists if you use the option
#echo "15715818" > OGRIDFILE
echo "Reset counter $file"
echo "0" > ${OGRIDFILE}

if [ -x "/datadisk2/out/all_merged.osm" ] && [ -x "/datadisk2/out/all_picc_merged.osm" ]
    echo "${GREEM}OSMOSIS GENERAL MERGE PICC/GRB${RESET}"
    echo "============="

    osmosis  \
    --rx /datadisk2/out/all_merged.osm  \
    --rx /datadisk2/out/all_picc_merged.osm  \
    --merge  \
    --wx /datadisk2/out/all_general_merged.osm

    if [ $? -eq 0 ]
    then
        echo "${GREEN}Successfully merged GRB AND PICC sources${RESET}"
        #cd /usr/local/src/grb && rm -f *.zip
        echo "${GREEN}Cleaning up diskspace - removing parsed files${RESET}"
        rm -f /datadisk2/out/all_merged.osm
        rm -f /datadisk2/out/all_picc_merged.osm
    else
    echo "${RED}Could not merge sources file${RESET}" >&2
    exit 1
    fi
fi

if [ ! -x "/datadisk2/out/all_merged.osm" ] && [ -x "/datadisk2/out/all_picc_merged.osm" ]
    echo "${GREEN}Only have PICC sources, renaming file for import${RESET}"
    mv /datadisk2/out/all_picc_merged.osm /datadisk2/out/all_general_merged.osm
fi

if [ -x "/datadisk2/out/all_merged.osm" ] && [ ! -x "/datadisk2/out/all_picc_merged.osm" ]
    echo "${GREEN}Only have GRB sources, renaming file for import${RESET}"
    mv /datadisk2/out/all_merged.osm /datadisk2/out/all_general_merged.osm
fi

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

