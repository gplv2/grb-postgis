#!/bin/bash -e

set -o allexport
source /tmp/configs/variables
set +o allexport

# Screen colors using tput

RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`

OGRIDFILE=ogr2osm.id

cd /usr/local/src/grb

echo "${GREEN}Processing URBIS data${RESET}"

# This script has been converted from the beta development site

# We need to keep track of the OGRIDFILE id as it allows us to incrementally process files instead of making a huge one while still keeping osm id unique across files
# default value is zero but the file does need to exists if you use the option
#echo "15715818" > OGRIDFILE

# If the file already exists, we need to contue counting from theer
if [ ! -f ${OGRIDFILE} ]; then
    echo "Reset counter $file"
    echo "${OSM_ID_START}" > ${OGRIDFILE}
fi

# urbis specific, use postgresql data dump 

# alter role "grb-data" IN DATABASE urbis set search_path = "URBIS_DIST_M7",public;
# create extension postgis;
# CREATE DATABASE "urbis" WITH OWNER "grb-data" ENCODING='UTF-8';
# UrbAdm_Schema.sql
# UrbAdm_Data.sql

echo "${GREEN}Loading up URBIS database${RESET}"

echo 'CREATE DATABASE "urbis" WITH OWNER "grb-data" ENCODING="UTF-8"' | psql -U postgres -h 127.0.0.1
echo 'CREATE EXTENSION postgis' | psql -U postgres -h 127.0.0.1 -d urbis
echo 'ALTER ROLE "grb-data" IN DATABASE urbis SET search_path = "URBIS_DIST_M7",public;' | psql -U ${DBUSER} -d ${DBURBIS} -h 127.0.0.1

psql -U ${DBUSER} -d ${DBURBIS} -h 127.0.0.1 -f URBISPG/postgresql/UrbAdm_Schema.sql
psql -U ${DBUSER} -d ${DBURBIS} -h 127.0.0.1 -f URBISPG/postgresql/UrbAdm_Data.sql

echo "${GREEN}Processing URBIS shape files${RESET}"

for file in URBIS/shp/UrbAdm_BUILDING.shp

do
 echo "Processing $file"
 dirname=$(dirname "$file")
 filename=$(basename "$file")
 extension="${filename##*.}"
 filename="${filename%.*}"
 #entity=${filename:0:3} # Gba/Gbg
 # force URBIS to Gbg logic since it's not the same as GRB but we only do building entities for now
 entity=Urbis

 echo $dirname
 echo "${GREEN}Cleanup parsed${RESET}"
 echo "=============="
 rm -Rf "${filename}_parsed"
 echo "${GREEN}OGR FILE INFO${RESET}"
 echo "============="
 /usr/local/bin/ogrinfo -al -ro -so ${dirname}/${filename}.shp
 echo ""

 echo "${GREEN}OGR2OGR${RESET}"
 echo "======="
 echo /usr/local/bin/ogr2ogr -s_srs "EPSG:31370" -t_srs "EPSG:4326" "${filename}_parsed" ${dirname}/${filename}.shp -overwrite

 /usr/local/bin/ogr2ogr -s_srs "EPSG:31370" -t_srs "EPSG:4326" "${filename}_parsed" ${dirname}/${filename}.shp -overwrite

 echo ""
 echo "${GREEN}OGR2OSM${RESET}"
 echo "======="
 rm -f "${filename}.osm"
 echo /usr/local/bin/ogr2osm/ogr2osm.py --idfile=${OGRIDFILE} --positive-id --saveid=${OGRIDFILE} "${filename}_parsed/${filename}.shp"
 /usr/local/bin/ogr2osm/ogr2osm.py --idfile=${OGRIDFILE} --positive-id --saveid=${OGRIDFILE} "${filename}_parsed/${filename}.shp"
 echo ""

# using sed to modify the data before import, it's a lot faster than queries but you need to be careful, those replacements have been carefully selected and tested in the beta site

# GBG
 if [ $entity == 'Urbis' ]
    then
    echo "${GREEN}running Urbis sed${RESET}"
    # mapping the entities to the OSM equivalent
    cp "${filename}.osm" "${filename}_keep_debug.osm"
    sed -e 's/CATEGORY/building/g;s/ID/source:geometry:oidn/g;s/tag k=\"BEGIN_LIFE\" v=\".*\"/tag k="source:geometry:entity" v="Urbis"/g;' -i "${filename}.osm"
    # this line is needed for the tools to work so we need to add it to the osm file using sed to replace
    sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

done

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully parsed URBIS sources${RESET}"
else
  echo "${RED}Could not process URBIS sources file${RESET}" >&2
  exit 1
fi

echo "${GREEM}OSMOSIS MERGE${RESET}"
echo "============="

mv UrbAdm_BUILDING.osm /datadisk2/out/all_urbis_merged.osm

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully moved URBIS sources (no need to merge) ${RESET}"
    #echo "Cleaning up diskspace - removing zip files"
    #cd /usr/local/src/grb && rm -f *.zip
    #echo "${GREEN}Cleaning up diskspace - removing parsed files${RESET}"
else
  echo "${RED}Could not move sources file${RESET}" >&2
  exit 1
fi

# echo "unmounting zip files"  # why bother, we kinda need them all the time
# # URBIS
# fusermount -u /usr/local/src/grb/URBIS

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

