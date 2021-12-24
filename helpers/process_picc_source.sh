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

echo "${GREEN}Processing PICC data${RESET}"

# This script has been converted from the beta development site

# We need to keep track of the OGRIDFILE id as it allows us to incrementally process files instead of making a huge one while still keeping osm id unique across files
# default value is zero but the file does need to exists if you use the option
#echo "15715818" > OGRIDFILE

# If the file already exists, we need to contue counting from theer
if [ ! -f ${OGRIDFILE} ]; then
    echo "Reset counter $file"
    echo "0" > ${OGRIDFILE}
fi

for file in NAMUR/CONSTR_BATIEMPRISE.shp LIEGE/CONSTR_BATIEMPRISE.shp HAINAUT/CONSTR_BATIEMPRISE.shp LUXEMBOURG/CONSTR_BATIEMPRISE.shp BRABANT/CONSTR_BATIEMPRISE.shp

do
 echo "Processing $file"
 dirname=$(dirname "$file")
 filename=$(basename "$file")
 extension="${filename##*.}"
 filename="${filename%.*}"
 #entity=${filename:0:3} # Gba/Gbg
 # force PICC to Gbg logic since it's not the same as GRB but we only do building entities for now
 entity=Picc

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
 echo /usr/local/bin/ogr2ogr -s_srs "EPSG:31370" -t_srs "EPSG:4326" "${filename}_${dirname}_parsed" ${dirname}/${filename}.shp -overwrite

 /usr/local/bin/ogr2ogr -s_srs "EPSG:31370" -t_srs "EPSG:4326" "${filename}_${dirname}_parsed" ${dirname}/${filename}.shp -overwrite

 echo ""
 echo "${GREEN}OGR2OSM${RESET}"
 echo "======="
 rm -f "${filename}_${dirname}.osm"
 echo /usr/local/bin/ogr2osm/ogr2osm.py --idfile=${OGRIDFILE} --positive-id --saveid=${OGRIDFILE} "${filename}_${dirname}_parsed/${filename}.shp"
 /usr/local/bin/ogr2osm/ogr2osm.py --idfile=${OGRIDFILE} --positive-id --saveid=${OGRIDFILE} "${filename}_${dirname}_parsed/${filename}.shp"
 echo "${GREEN}Rename ${filename}.osm to province version ${filename}_${dirname}.osm ${RESET}"
 mv ${filename}.osm ${filename}_${dirname}.osm
 echo ""

# using sed to modify the data before import, it's a lot faster than queries but you need to be careful, those replacements have been carefully selected and tested in the beta site

# GBG
 if [ $entity == 'Picc' ]
    then
    echo "${GREEN}running Picc sed${RESET}"
    # mapping the entities to the OSM equivalent
    sed -e 's/NATUR_CODE/building/g;s/OBJECTID/source:geometry:oidn/g;s/DATE_MODIF/source:geometry:date/g;s/BAT/house/g;s/ANE/yes/g;s/BUI/yes/g;s/tag k=\"CODE_WALTO\"\sv=\"([A-Z])\w+\"/tag k="source:geometry:entity" v="Picc"/g' -i "${filename}_${dirname}.osm"
    # this line is needed for the tools to work so we need to add it to the osm file using sed to replace
    sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}_${dirname}.osm"
 fi

#   sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Knw"/g' -i "${filename}.osm"
#    # this line is needed for osmosis to accept the OSM file so we need to add it to the osm file using sed to replace
#   sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
#   sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/\"afdak\"/\"roof\"/g;s/\"ingezonken garagetoegang\"/\"garage3\"/g;s/\"verheven garagetoegang\"/\"garage4\"/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gba"/g' -i "${filename}.osm"
#    # this line is needed for osmosis to accept the OSM file we crated  so we need to add it to the osm file using sed to replace
#   sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"

done

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully parsed PICC sources${RESET}"
else
  echo "${RED}Could not process PICC sources file${RESET}" >&2
  exit 1
fi

# NAMUR/CONSTR_BATIEMPRISE.shp LIEGE/CONSTR_BATIEMPRISE.shp HAINAUT/CONSTR_BATIEMPRISE.shp LUXEMBOURG/CONSTR_BATIEMPRISE.shp BRABANT/CONSTR_BATIEMPRISE.shp

echo "${GREEM}OSMOSIS MERGE${RESET}"
echo "============="

osmosis  \
--rx CONSTR_BATIEMPRISE_NAMUR.osm  \
--rx CONSTR_BATIEMPRISE_BRABANT.osm  \
--rx CONSTR_BATIEMPRISE_LIEGE.osm  \
--rx CONSTR_BATIEMPRISE_HAINAUT.osm  \
--rx CONSTR_BATIEMPRISE_LUXEMBOURG.osm  \
--merge  \
--merge  \
--merge  \
--merge  \
--wx /datadisk2/out/all_picc_merged.osm

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully merged PICC sources${RESET}"
    #echo "Cleaning up diskspace - removing zip files"
    #cd /usr/local/src/grb && rm -f *.zip
    echo "${GREEN}Cleaning up diskspace - removing parsed files${RESET}"
    rm -f NAMUR.osm
    rm -f HAINAUT.osm
    rm -f LIEGE.osm
    rm -f LUXEMBOURG.osm
    rm -f BRABANT.osm
else
  echo "${RED}Could not merge sources file${RESET}" >&2
  exit 1
fi

# echo "unmounting zip files"  # why bother, we kinda need them all the time
# # PICC
# fusermount -u /usr/local/src/grb/NAMUR
# fusermount -u /usr/local/src/grb/LIEGE
# fusermount -u /usr/local/src/grb/BRABANT
# fusermount -u /usr/local/src/grb/HAINAUT
# fusermount -u /usr/local/src/grb/LUXEMBOURG

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

