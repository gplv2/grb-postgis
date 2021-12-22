#!/bin/bash -e

set -o allexport
source /tmp/configs/variables
set +o allexport

OGRIDFILE=ogr2osm.id

cd /usr/local/src/grb

echo ""
echo "${GREEN}Addressing${RESET}"
echo "======"

cd ~${DEPLOY_USER}

# address directly in the database using DBF database file, the tool will take care of all anomalities encountered (knw/Gbg)
php grb2osm/grb2osm.php -f /usr/local/src/grb/GRBgis_20001/Shapefile/TblGbgAdr20001B500.dbf,/usr/local/src/grb/GRBgis_10000/Shapefile/TblGbgAdr10000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblGbgAdr30000B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblGbgAdr40000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblGbgAdr70000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblKnwAdr30000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblKnwAdr70000B500.dbf,/usr/local/src/grb/GRBgis_20001/Shapefile/TblKnwAdr20001B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblKnwAdr40000B500.dbf

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

