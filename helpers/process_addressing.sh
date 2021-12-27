#!/bin/bash -e

set -o allexport
source /tmp/configs/variables
set +o allexport

# Screen colors using tput

RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`

cd /usr/local/src/grb

echo ""
echo "${GREEN}Addressing${RESET}"
echo "======"

cd /home/${DEPLOY_USER}

echo "${GREEN}GRB addresses${RESET}"
# address directly in the database using DBF database file, the tool will take care of all anomalities encountered (knw/Gbg)
php grb2osm/grb2osm.php -f /usr/local/src/grb/GRBgis_20001/Shapefile/TblGbgAdr20001B500.dbf,/usr/local/src/grb/GRBgis_10000/Shapefile/TblGbgAdr10000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblGbgAdr30000B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblGbgAdr40000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblGbgAdr70000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblKnwAdr30000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblKnwAdr70000B500.dbf,/usr/local/src/grb/GRBgis_20001/Shapefile/TblKnwAdr20001B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblKnwAdr40000B500.dbf

echo "${GREEN}PICC addresses${RESET}"
# address picc directly in DB, this tool will take care of duplicate geometries
php grb2osm/grb2osm.php -p -f /usr/local/src/grb/NAMUR/ADRESS_POINT.dbf,/usr/local/src/grb/HAINAUT/ADRESS_POINT.dbf,/usr/local/src/grb/LIEGE/ADRESS_POINT.dbf,/usr/local/src/grb/LUXEMBOURG/ADRESS_POINT.dbf,/usr/local/src/grb/BRABANT/ADRESS_POINT.dbf

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully imported addresses into DB${RESET}"
else
  echo "${RED}Could not address into DB${RESET}" >&2
  exit 1
fi

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

