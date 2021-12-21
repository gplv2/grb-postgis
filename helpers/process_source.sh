#!/bin/bash -e

set -o allexport
source /tmp/configs/variables
set +o allexport

OGRIDFILE=ogr2osm.id

DBUSER=grb-data
DBDATA=grb_api

cd /usr/local/src/grb

# This script has been converted from the beta development site

echo "${GREEN}Processing GRB source${RESET}"

# We need to keep track of the OGRIDFILE id as it allows us to incrementally process files instead of making a huge one while still keeping osm id unique across files
# default value is zero but the file does need to exists if you use the option
#echo "15715818" > OGRIDFILE
echo "Reset counter $file"
echo "0" > ${OGRIDFILE}

# If you are low on diskspace, you can use fuse to mount the zips as device in user space
# fuse-zip -o ro ../php/files/GRBgis_40000.zip GRBgis_40000
# fusermount -u GRBgis_40000

#fuse-zip -o ro files/GRBgis_10000.zip GRBgis_10000
#fuse-zip -o ro files/GRBgis_20001.zip GRBgis_20001
#fuse-zip -o ro files/GRBgis_30000.zip GRBgis_30000
#fuse-zip -o ro files/GRBgis_40000.zip GRBgis_40000
#fuse-zip -o ro files/GRBgis_70000.zip GRBgis_70000
#fuse-zip -o ro files/GRBgis_04000.zip GRBgis_04000

for file in GRBgis_10000/Shapefile/Gbg*.shp GRBgis_20001/Shapefile/Gbg*.shp GRBgis_30000/Shapefile/Gbg*.shp GRBgis_40000/Shapefile/Gbg*.shp GRBgis_70000/Shapefile/Gbg*.shp GRBgis_10000/Shapefile/Gba*.shp GRBgis_20001/Shapefile/Gba*.shp GRBgis_30000/Shapefile/Gba*.shp GRBgis_40000/Shapefile/Gba*.shp GRBgis_70000/Shapefile/Gba*.shp GRBgis_10000/Shapefile/Knw*.shp GRBgis_20001/Shapefile/Knw*.shp GRBgis_30000/Shapefile/Knw*.shp GRBgis_40000/Shapefile/Knw*.shp GRBgis_70000/Shapefile/Knw*.shp

do
 echo "Processing $file"
 dirname=$(dirname "$file")
 filename=$(basename "$file")
 extension="${filename##*.}"
 filename="${filename%.*}"
 entity=${filename:0:3} # Gba/Gbg

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
 if [ $entity == 'Gbg' ]
    then
    echo "${GREEN}running gbg sed${RESET}"
    # mapping the entities to the OSM equivalent
 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gbg"/g' -i "${filename}.osm"
    # this line is needed for the tools to work so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

# we problably need to run the second sed for the first line only like this sed -i '1!b;s/test/blah/' file
# KNW
 if [ $entity == 'Knw' ]
    then
    echo "${GREEN}running gbg sed${RESET}"
    # mapping the entities to the OSM equivalent
 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Knw"/g' -i "${filename}.osm"
    # this line is needed for osmosis to accept the OSM file so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

# GBA
 if [ $entity == 'Gba' ]
    then
    echo "${GREEN}running gba sed${RESET}"
    # mapping the entities to the OSM equivalent
 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/\"afdak\"/\"roof\"/g;s/\"ingezonken garagetoegang\"/\"garage3\"/g;s/\"verheven garagetoegang\"/\"garage4\"/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gba"/g' -i "${filename}.osm"
    # this line is needed for osmosis to accept the OSM file we crated  so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

done

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully parsed GRB sources${RESET}"
else
  echo "${RED}Could not process sources file${RESET}" >&2
  exit 1
fi

echo "${GREEM}OSMOSIS MERGE${RESET}"
echo "============="

osmosis  \
--rx Gbg10000B500.osm  \
--rx Gbg20001B500.osm  \
--rx Gbg30000B500.osm  \
--rx Gbg40000B500.osm  \
--rx Gbg70000B500.osm  \
--rx Gba10000B500.osm  \
--rx Gba20001B500.osm  \
--rx Gba30000B500.osm  \
--rx Gba40000B500.osm  \
--rx Gba70000B500.osm  \
--rx Knw10000B500.osm  \
--rx Knw20001B500.osm  \
--rx Knw30000B500.osm  \
--rx Knw40000B500.osm  \
--rx Knw70000B500.osm  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--wx /datadisk2/out/all_merged.osm

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully merged GRB sources${RESET}"
    #echo "Cleaning up diskspace - removing zip files"
    #cd /usr/local/src/grb && rm -f *.zip
    echo "${GREEN}Cleaning up diskspace - removing parsed files${RESET}"
    rm -f Gbg10000B500.osm
    rm -f Gbg20001B500.osm
    rm -f Gbg30000B500.osm
    rm -f Gbg40000B500.osm
    rm -f Gbg70000B500.osm
    rm -f Gba10000B500.osm
    rm -f Gba20001B500.osm
    rm -f Gba30000B500.osm
    rm -f Gba40000B500.osm
    rm -f Gba70000B500.osm
    rm -f Knw10000B500.osm
    rm -f Knw20001B500.osm
    rm -f Knw30000B500.osm
    rm -f Knw40000B500.osm
    rm -f Knw70000B500.osm
else
  echo "${RED}Could not merge sources file${RESET}" >&2
  exit 1
fi

#echo "unmounting zip files"  | why bother, we need them for addressing
## GRB
#fusermount -u /usr/local/src/grb/GRBgis_10000
#fusermount -u /usr/local/src/grb/GRBgis_20001
#fusermount -u /usr/local/src/grb/GRBgis_30000
#fusermount -u /usr/local/src/grb/GRBgis_40000
#fusermount -u /usr/local/src/grb/GRBgis_70000

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

