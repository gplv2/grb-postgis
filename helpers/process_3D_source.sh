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

# This script has been converted from the beta development site

# We need to keep track of the OGRIDFILE id as it allows us to incrementally process files instead of making a huge one while still keeping osm id unique across files
# default value is zero but the file does need to exists if you use the option
#echo "15715818" > OGRIDFILE
if [ ! -f ${OGRIDFILE} ]; then
    echo "Reset counter $file"
    echo "${OSM_ID_3D_START}" > ${OGRIDFILE}
fi

# If you are low on diskspace, you can use fuse to mount the zips as device in user space
# fuse-zip -o ro ../php/files/GRBgis_40000.zip GRBgis_40000
# fusermount -u GRBgis_40000

#fuse-zip -o ro files/3D_GRBgis_10000.zip 3D_GRB_10000
# 3D_GRB_04000 3D_GRB_30000 3D_GRB_20001 3D_GRB_40000 3D_GRB_70000 3D_GRB_10000

for file in 3D_GRB_04000/Shapefile/GRBGebL1D2*.shp 3D_GRB_30000/Shapefile/GRBGebL1D2*.shp 3D_GRB_20001/Shapefile/GRBGebL1D2*.shp 3D_GRB_40000/Shapefile/GRBGebL1D2*.shp 3D_GRB_70000/Shapefile/GRBGebL1D2*.shp 3D_GRB_10000/Shapefile/GRBGebL1D2*.shp

do
 echo "Processing $file"
 dirname=$(dirname "$file")
 filename=$(basename "$file")
 extension="${filename##*.}"
 filename="${filename%.*}"
 entity=${filename:0:3} # Gba/Gbg

 # table prefix
 TABLEPREFIX=lidar

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
 echo "running sed\n"
# mapping the entities to the OSM equivalent
 sed -e 's/LBLTYPE/building/g;s/GRB_OIDN/source:geometry:oidn/g;s/GRB_UIDN/source:geometry:uidn/g;s/ENTITEIT/source:geometry:entity/g;s/DATUM_GRB/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g' -i "${filename}.osm"
 sed -e 's/DATUM_LID/source:lidar:date/g;s/H_KWAL/source:lidar:quality/g;s/STRAATNMID/STRAAT_NM_ID/g' -i "${filename}.osm"
 sed -e 's/STRAATNM/addr:street/g' -i "${filename}.osm"
#sed -e 's/LBLTYPE/building/g;s/GRB_OIDN/source:geometry:oidn/g;s/GRB_UIDN/source:geometry:uidn/g;s/ENTITEIT/source:geometry:entity/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gbg"/g' -i "${filename}.osm"
# this line is needed for the tools to work so we need to add it to the osm file using sed to replace
 sed -e 's/\"afdak\"/\"roof\"/g;s/\"ingezonken garagetoegang\"/\"garage3\"/g;s/\"verheven garagetoegang\"/\"garage4\"/g' -i "${filename}.osm"
 sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"

done

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully parsed GRB 3D sources${RESET}"
else
  echo "${RED}Could not process sources file${RESET}" >&2
  exit 1
fi

echo "${GREEM}OSMOSIS MERGE${RESET}"
echo "============="

osmosis  \
--rx GRBGebL1D204000B500.osm  \
--rx GRBGebL1D210000B500.osm  \
--rx GRBGebL1D220001B500.osm  \
--rx GRBGebL1D230000B500.osm  \
--rx GRBGebL1D240000B500.osm  \
--rx GRBGebL1D270000B500.osm  \
--merge  \
--merge  \
--merge  \
--merge  \
--merge  \
--wx /datadisk2/out/all_3d_merged.osm

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully merged GRB 3D sources${RESET}"
    echo "Cleaning up diskspace - removing 3D zip files"
    cd /usr/local/src/grb && rm -f *.zip
    echo "Cleaning up diskspace - removing parsed files"
    rm -f GRBGebL1D204000B500.osm
    rm -f GRBGebL1D210000B500.osm
    rm -f GRBGebL1D220001B500.osm
    rm -f GRBGebL1D230000B500.osm
    rm -f GRBGebL1D240000B500.osm
    rm -f GRBGebL1D270000B500.osm
else
  echo "${RED}Could not merge sources file${RESET}" >&2
  exit 1
fi

# postgresql work

echo ""
echo "${GREEN}IMPORT${RESET}"
echo "======"

# /usr/bin/osm2pgsql --slim --create --cache 4000 --number-processes 3 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d ${DB} -U ${USER} /datadisk2/out/all_merged.osm -H grb-db-0
/usr/local/bin/osm2pgsql --slim --drop --create -l --cache ${CACHE} --number-processes ${THREADS} --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto-3d.style --multi-geometry -d ${DB} -U ${USER} /datadisk2/out/all_3d_merged.osm -H 127.0.0.1 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace --prefix ${TABLEPREFIX}

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully imported processed 3D GRB sources into PGSQL${RESET}"
else
    echo "${GREEN}Could not import merged source files${RESET}" >&2
    exit 1
fi

echo "${GREEN}Creating additional indexes...${RESET}"

echo "CREATE INDEX ${TABLEPREFIX}_grb_source_index_p1 ON ${TABLEPREFIX}_polygon USING btree (\"source:geometry:uidn\" COLLATE pg_catalog.\"default\") TABLESPACE indexspace;" | psql -U ${USER} ${DB} -h 127.0.0.1
echo "CREATE INDEX ${TABLEPREFIX}_grb_source_index_p2 ON ${TABLEPREFIX}_polygon USING btree (\"source:geometry:oidn\" COLLATE pg_catalog.\"default\") TABLESPACE indexspace;" | psql -U ${USER} ${DB} -h 127.0.0.1
echo "CREATE INDEX ${TABLEPREFIX}_grb_source_index_p3 ON ${TABLEPREFIX}_polygon USING btree (\"source:geometry:ref\" COLLATE pg_catalog.\"default\") TABLESPACE indexspace;" | psql -U ${USER} ${DB} -h 127.0.0.1
echo "CREATE INDEX ${TABLEPREFIX}_grb_source_ent_p ON ${TABLEPREFIX}_polygon USING btree (\"source:geometry:entity\" COLLATE pg_catalog.\"default\") TABLESPACE indexspace;" | psql -U ${USER} ${DB} -h 127.0.0.1

# setup source tag for all objects imported
echo "UPDATE ${TABLEPREFIX}_polygon SET "source" = 'GRB';" | psql -U ${USER} ${DB} -h 127.0.0.1

# more indexes
echo "CREATE INDEX ${TABLEPREFIX}_osm_src_index_p ON ${TABLEPREFIX}_polygon USING btree (\"source\" COLLATE pg_catalog.\"default\") TABLESPACE indexspace;" | psql -U ${USER} ${DB} -h 127.0.0.1

# use a query to update 'trap' as this word is a bit too generic and short to do with sed tricks
echo "UPDATE ${TABLEPREFIX}_polygon set highway='steps', building='' where building='trap';" | psql -U ${USER} ${DB} -h 127.0.0.1

echo "${GREEN}creating additional indexes...${RESET}"

cat > /tmp/create.3D.indexes.sql << EOF
CREATE INDEX idx_${TABLEPREFIX}_osm_line_nobridge ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE ((man_made <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) OR man_made IS NOT NULL);
CREATE INDEX idx_${TABLEPREFIX}_mm_null ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE (man_made IS NOT NULL);
CREATE INDEX idx_${TABLEPREFIX}_no_bridge ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE (bridge <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_${TABLEPREFIX}_hw_null ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE (highway IS NOT NULL);
CREATE INDEX idx_${TABLEPREFIX}_no_hw ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE (highway <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_${TABLEPREFIX}_no_b ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE (building <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_${TABLEPREFIX}_b_null ON ${TABLEPREFIX}_polygon USING gist (way) TABLESPACE indexspace WHERE (building IS NOT NULL);
EOF

# These are primarily if you hook up a bbox client script to it, not really interesting when all you want to do is export the built database to a file
cat /tmp/create.3D.indexes.sql | psql -U ${USER} ${DB} -h 127.0.0.1

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully created indexes/updates${RESET}"
else
  echo "${RED}Could not execute indexing/updates${RESET}" >&2
  exit 1
fi

# datatype fixes
cat > /tmp/datatype.3D.tags.sql << EOF
ALTER TABLE ${TABLEPREFIX}_polygon alter column "source:geometry:oidn" TYPE INTEGER  USING ("source:geometry:oidn"::integer) ;
ALTER TABLE ${TABLEPREFIX}_polygon alter column "source:geometry:uidn" TYPE INTEGER  USING ("source:geometry:uidn"::integer) ;
EOF

cat /tmp/datatype.3D.tags.sql | psql -U ${USER} ${DB} -h 127.0.0.1

# change tags in DB
# DELETE FROM planet_osm_polygon WHERE building IN ('garage3','pijler','rooster','zichtbare onderkeldering','cultuur-historisch monument','cabine','garage4','staketsel','gebouw afgezoomd met virtuele gevels','tunnelmond');
cat > /tmp/update.3D.tags.sql << EOF
UPDATE ${TABLEPREFIX}_polygon SET fixme='verdieping, correct the building tag, add building:level and building:min_level before upload in JOSM!', building='yes' where building='verdieping';
UPDATE ${TABLEPREFIX}_polygon SET building='yes', man_made='water_tower' WHERE building='watertoren';
UPDATE ${TABLEPREFIX}_polygon SET man_made='tower', "tower:type"='cooling' , building='yes' WHERE building='koeltoren';
UPDATE ${TABLEPREFIX}_polygon SET building='',tags=hstore('building:part', 'yes'), foot='designated', layer='1', fixme='This is a walking bridge between buildings, please review and complete all tags, use way osmid 118022697 as example' WHERE building='loopbrug';
UPDATE ${TABLEPREFIX}_polygon SET man_made='chimney', building='', fixme='Add the chimney type and optionally building in case the chimney is part of a building' WHERE building='schoorsteen';
UPDATE ${TABLEPREFIX}_polygon SET man_made='works', building='' , fixme='This installation is chemical in nature, refine where possible by adding a product=* tag' WHERE building='chemische installatie';
UPDATE ${TABLEPREFIX}_polygon SET man_made='pier', building='' , fixme='This is a havendam, which should be a pier, make sure to verify this' WHERE building='havendam';
UPDATE ${TABLEPREFIX}_polygon SET man_made='mast', building='' , fixme='This is a mast , either high voltage powerline or public TV broadcast, refine this with power, tower:type, height tags or/and communication:* namespace tags, see wiki for more' WHERE building='hoogspanningsmast / openbare TV mast';
UPDATE ${TABLEPREFIX}_polygon SET man_made='storage_tank', building='', fixme='Add the silo type and optionally building type, refine this with content=* see wiki for more information' WHERE building='silo, opslagtank';
UPDATE ${TABLEPREFIX}_polygon SET man_made='groyne', building='', fixme='This can be either: golfbreker, strandhoofd of lage havendam' WHERE building='golfbreker, strandhoofd en lage havendam';
UPDATE ${TABLEPREFIX}_polygon SET man_made='bridge', building='' WHERE building='overbrugging';
UPDATE ${TABLEPREFIX}_polygon SET man_made='weir', fixme='Waterbouwkundig constructie: Doublecheck this tag carefully, it can be a weir, lock_gate, dam etc. check the wiki for the waterways key for more information. When in doubt, delete this object', building='' WHERE building='waterbouwkundig constructie';
EOF

# These are primarily if you hook up a bbox client script to it, not really interesting when all you want to do is export the built database to a file
cat /tmp/update.3D.tags.sql | psql -U ${USER} ${DB} -h 127.0.0.1

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully Updated/mapped tags to their OSM counterparts${RESET}"
else
  echo "${RED}Could not execute deletes/updates${RESET}" >&2
  exit 1
fi

# more to change using queries :

#    <tag k="building" v="cabine"/>
#    <tag k="building" v="chemische installatie"/>
#    <tag k="building" v="cultuur-historisch monument"/>
#    <tag k="building" v="golfbreker, strandhoofd en lage havendam"/>
#    <tag k="building" v="havendam"/>
#    <tag k="building" v="hoogspanningsmast / openbare TV mast"/>
#    <tag k="building" v="koeltoren"/>
#    <tag k="building" v="overbrugging"/>
#    <tag k="building" v="pijler"/>
#    <tag k="building" v="rooster"/>
#    <tag k="building" v="schoorsteen"/>
#    <tag k="building" v="silo, opslagtank"/>
#    <tag k="building" v="staketsel"/>
#    <tag k="building" v="tunnelmond"/>
#    <tag k="building" v="waterbouwkundig constructie"/>
#    <tag k="building" v="watertoren"/>

# quick fix
#cd ~

# address directly in the database using DBF database file, the tool will take care of all anomalities encountered (knw/Gbg)
# grb2osm/grb2osm.php -f /usr/local/src/grb/GRBgis_20001/Shapefile/TblGbgAdr20001B500.dbf,/usr/local/src/grb/GRBgis_10000/Shapefile/TblGbgAdr10000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblGbgAdr30000B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblGbgAdr40000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblGbgAdr70000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblKnwAdr30000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblKnwAdr70000B500.dbf,/usr/local/src/grb/GRBgis_20001/Shapefile/TblKnwAdr20001B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblKnwAdr40000B500.dbf

#if [ $? -eq 0 ]
#then
#  echo "Successfully imported addresses into DB"
#else
#  echo "Could not address into DB" >&2
#  exit 1
#fi

# 3D GRB
fusermount -u /usr/local/src/grb/3D_GRB_04000
fusermount -u /usr/local/src/grb/3D_GRB_30000
fusermount -u /usr/local/src/grb/3D_GRB_20001
fusermount -u /usr/local/src/grb/3D_GRB_40000
fusermount -u /usr/local/src/grb/3D_GRB_70000
fusermount -u /usr/local/src/grb/3D_GRB_10000

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

