#!/bin/bash -e

set -o allexport
source /tmp/configs/variables
set +o allexport

# Screen colors using tput

RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`

cd /usr/local/src/grb

# This script has been converted from the beta development site

if [ ${GRB} -eq 1 ] && [ ${PICC} -eq 1 ] && [ ${URBIS} -eq 0 ]; then
    if [ -f "/datadisk2/out/all_merged.osm" ] && [ -f "/datadisk2/out/all_picc_merged.osm" ]; then
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
fi

if [ ${GRB} -eq 1 ] && [ ${PICC} -eq 0 ] && [ ${URBIS} -eq 1 ]; then
    if [ -f "/datadisk2/out/all_merged.osm" ] && [ -f "/datadisk2/out/all_urbis_merged.osm" ]; then
        echo "${GREEM}OSMOSIS GENERAL MERGE URBIS/GRB${RESET}"
        echo "============="

        osmosis  \
            --rx /datadisk2/out/all_merged.osm  \
            --rx /datadisk2/out/all_urbis_merged.osm  \
            --merge  \
            --wx /datadisk2/out/all_general_merged.osm

        if [ $? -eq 0 ]
        then
            echo "${GREEN}Successfully merged GRB AND PICC sources${RESET}"
            #cd /usr/local/src/grb && rm -f *.zip
            echo "${GREEN}Cleaning up diskspace - removing parsed files${RESET}"
            rm -f /datadisk2/out/all_merged.osm
            rm -f /datadisk2/out/all_urbis_merged.osm
        else
            echo "${RED}Could not merge sources file${RESET}" >&2
            exit 1
        fi
    fi
fi

if [ ${GRB} -eq 1 ] && [ ${PICC} -eq 1 ] && [ ${URBIS} -eq 1 ]; then
    if [ -f "/datadisk2/out/all_merged.osm" ] && [ -f "/datadisk2/out/all_urbis_merged.osm" ] && [ -f "/datadisk2/out/all_picc_merged.osm" ]; then
        echo "${GREEM}OSMOSIS GENERAL MERGE PICC/URBIS/GRB${RESET}"
        echo "============="

        osmosis  \
            --rx /datadisk2/out/all_merged.osm  \
            --rx /datadisk2/out/all_urbis_merged.osm  \
            --rx /datadisk2/out/all_picc_merged.osm  \
            --merge  \
            --merge  \
            --wx /datadisk2/out/all_general_merged.osm

        if [ $? -eq 0 ]
        then
            echo "${GREEN}Successfully merged GRB, URBIS AND PICC sources${RESET}"
            #cd /usr/local/src/grb && rm -f *.zip
            echo "${GREEN}Cleaning up diskspace - removing parsed files${RESET}"
            rm -f /datadisk2/out/all_merged.osm
            rm -f /datadisk2/out/all_urbis_merged.osm
            rm -f /datadisk2/out/all_picc_merged.osm
        else
            echo "${RED}Could not merge sources file${RESET}" >&2
            exit 1
        fi
    fi
fi

if [ ${GRB} -eq 0 ] && [ ${PICC} -eq 1 ] && [ ${URBIS} -eq 0 ]; then
    if [ ! -f "/datadisk2/out/all_merged.osm" ] && [ -f "/datadisk2/out/all_picc_merged.osm" ]; then
        echo "${GREEN}Only have PICC sources, renaming file for import${RESET}"
        mv /datadisk2/out/all_picc_merged.osm /datadisk2/out/all_general_merged.osm
    fi
fi

if [ ${GRB} -eq 0 ] && [ ${PICC} -eq 0 ] && [ ${URBIS} -eq 1 ]; then
    if [ ! -f "/datadisk2/out/all_merged.osm" ] && [ -f "/datadisk2/out/all_picc_merged.osm" ]; then
        echo "${GREEN}Only have URBIS sources, renaming file for import${RESET}"
        mv /datadisk2/out/all_urbis_merged.osm /datadisk2/out/all_general_merged.osm
    fi
fi

if [ ${GRB} -eq 1 ] && [ ${PICC} -eq 0 ] && [ ${URBIS} -eq 0 ]; then
    if [ -f "/datadisk2/out/all_merged.osm" ] && [ ! -f "/datadisk2/out/all_picc_merged.osm" ]; then
        echo "${GREEN}Only have GRB sources, renaming file for import${RESET}"
        mv /datadisk2/out/all_merged.osm /datadisk2/out/all_general_merged.osm
    fi
fi
# /datadisk2/out/all_urbis_merged.osm

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

