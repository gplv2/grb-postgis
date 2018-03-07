#!/bin/bash

cd /usr/local/src/grb

# This script has been converted from the beta development site

# We need to keep track of the ogr2osm id as it allows us to incrementally process files instead of making a huge one while still keeping osm id unique across files
# default value is zero but the file does need to exists if you use the option
#echo "15715818" > ogr2osm.id
echo "Reset counter $file"
echo "0" > ogr2osm.id

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

 echo $dirname
 echo "Cleanup parsed"
 echo "=============="
 rm -Rf "${filename}_parsed"
 echo "OGR FILE INFO"
 echo "============="
 /usr/local/bin/ogrinfo -al -so ${dirname}/${filename}.shp
 echo ""

 echo "OGR2OGR"
 echo "======="
 echo /usr/local/bin/ogr2ogr -s_srs "EPSG:31370" -t_srs "EPSG:4326" "${filename}_parsed" ${dirname}/${filename}.shp -overwrite

 /usr/local/bin/ogr2ogr -s_srs "EPSG:31370" -t_srs "EPSG:4326" "${filename}_parsed" ${dirname}/${filename}.shp -overwrite

 echo ""
 echo "OGR2OSM"
 echo "======="
 rm -f "${filename}.osm"
 echo /usr/local/bin/ogr2osm/ogr2osm.py --idfile=ogr2osm.id --positive-id --saveid=ogr2osm.id "${filename}_parsed/${filename}.shp"
 /usr/local/bin/ogr2osm/ogr2osm.py --idfile=ogr2osm.id --positive-id --saveid=ogr2osm.id "${filename}_parsed/${filename}.shp"
 echo ""

# using sed to modify the data before import, it's a lot faster than queries but you need to be careful, those replacements have been carefully selected and tested in the beta site

# GBG
echo "running sed\n"
# mapping the entities to the OSM equivalent
sed -e 's/LBLTYPE/building/g;s/GRB_OIDN/source:geometry:oidn/g;s/GRB_UIDN/source:geometry:uidn/g;s/ENTITEIT/source:geometry:entity/g;s/DATUM_GRB/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g' -i "${filename}.osm"
sed -e 's/DATUM_LID/source:lidar:date/g;s/H_KWAL/source:lidar:quality/g;s/STRAATNM/addr:streetname/g' -i "${filename}.osm"
#sed -e 's/LBLTYPE/building/g;s/GRB_OIDN/source:geometry:oidn/g;s/GRB_UIDN/source:geometry:uidn/g;s/ENTITEIT/source:geometry:entity/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gbg"/g' -i "${filename}.osm"
# this line is needed for the tools to work so we need to add it to the osm file using sed to replace
sed -e 's/\"afdak\"/\"roof\"/g;s/\"ingezonken garagetoegang\"/\"garage3\"/g;s/\"verheven garagetoegang\"/\"garage4\"/g' -i "${filename}.osm"
sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"

if [ $? -eq 0 ]
then
  echo "Successfully parsed 3D GRB sources"
else
  echo "Could not process sources file" >&2
  exit 1
fi

echo "OSMOSIS MERGE"
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
    echo "Successfully merged 3D GRB sources"
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
  echo "Could not merge sources file" >&2
  exit 1
fi

# postgresql work

 echo ""
 echo "IMPORT"
 echo "======"

# /usr/bin/osm2pgsql --slim --create --cache 4000 --number-processes 3 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d grb_api -U grb-data /datadisk2/out/all_merged.osm -H grb-db-0
/usr/local/bin/osm2pgsql --slim --create -l --cache 8000 --number-processes 3 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto-3d.style --multi-geometry -d grb_api -U grb-data /datadisk2/out/all_3d_merged.osm -H grb-db-0 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace --prefix lidar

if [ $? -eq 0 ]
then
  echo "Successfully imported processed 3D GRB sources into PGSQL"
else
  echo "Could not import merged source files" >&2
  exit 1
fi

echo "Creating additional indexes..."

echo 'CREATE INDEX lidar_grb_source_index_p ON lidar_polygon USING btree ("source:geometry:oidn" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U grb-data grb_api -h grb-db-0
echo 'CREATE INDEX lidar_grb_source_ent_p ON lidar_polygon USING btree ("source:geometry:entity" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U grb-data grb_api -h grb-db-0

# setup source tag for all objects imported
echo "UPDATE lidar_polygon SET "source" = 'GRB';" | psql -U grb-data grb_api -h grb-db-0

# more indexes
echo 'CREATE INDEX lidar_osm_src_index_p ON lidar_polygon USING btree ("source" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U grb-data grb_api -h grb-db-0

# use a query to update 'trap' as this word is a bit too generic and short to do with sed tricks
echo "UPDATE lidar_polygon set highway='steps', building='' where building='trap';" | psql -U grb-data grb_api -h grb-db-0

echo "creating additional indexes..."

cat > /tmp/create.indexes.sql << EOF
CREATE INDEX idx_lidar_osm_line_nobridge ON lidar_polygon USING gist (way) WHERE ((man_made <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) OR man_made IS NOT NULL) TABLESPACE indexspace;
CREATE INDEX idx_lid_mm_null ON lidar_polygon USING gist (way) WHERE (man_made IS NOT NULL) TABLESPACE indexspace;
CREATE INDEX idx_lid_no_bridge ON lidar_polygon USING gist (way) WHERE (bridge <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) TABLESPACE indexspace;
CREATE INDEX idx_lid_hw_null ON lidar_polygon USING gist (way) WHERE (highway IS NOT NULL) TABLESPACE indexspace;
CREATE INDEX idx_lid_no_hw ON lidar_polygon USING gist (way) WHERE (highway <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) TABLESPACE indexspace;
CREATE INDEX idx_lid_no_b ON lidar_polygon USING gist (way) WHERE (building <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) TABLESPACE indexspace;
CREATE INDEX idx_lid_b_null ON lidar_polygon USING gist (way) WHERE (building IS NOT NULL) TABLESPACE indexspace;
EOF

# These are primarily if you hook up a bbox client script to it, not really interesting when all you want to do is export the built database to a file
cat /tmp/create.indexes.sql | psql -U grb-data grb_api -h grb-db-0

if [ $? -eq 0 ]
then
  echo "Successfully created indexes/updates"
else
  echo "Could not execute indexing/updates" >&2
  exit 1
fi

# change tags in DB
# DELETE FROM planet_osm_polygon WHERE building IN ('garage3','pijler','rooster','zichtbare onderkeldering','cultuur-historisch monument','cabine','garage4','staketsel','gebouw afgezoomd met virtuele gevels','tunnelmond');
cat > /tmp/update.tags.sql << EOF
UPDATE planet_osm_polygon SET fixme='verdieping, correct the building tag, add building:level and building:min_level before upload in JOSM!', building='yes' where building='verdieping';
UPDATE planet_osm_polygon SET building='yes', man_made='water_tower' WHERE building='watertoren';
UPDATE planet_osm_polygon SET man_made='tower', "tower:type"='cooling' , building='yes' WHERE building='koeltoren';
UPDATE planet_osm_polygon SET building='',tags=hstore('building:part', 'yes'), foot='designated', layer='1', fixme='This is a walking bridge between buildings, please review and complete all tags, use way osmid 118022697 as example' WHERE building='loopbrug';
UPDATE planet_osm_polygon SET man_made='chimney', building='', fixme='Add the chimney type and optionally building in case the chimney is part of a building' WHERE building='schoorsteen';
UPDATE planet_osm_polygon SET man_made='works', building='' , fixme='This installation is chemical in nature, refine where possible by adding a product=* tag' WHERE building='chemische installatie';
UPDATE planet_osm_polygon SET man_made='pier', building='' , fixme='This is a havendam, which should be a pier, make sure to verify this' WHERE building='havendam';
UPDATE planet_osm_polygon SET man_made='mast', building='' , fixme='This is a mast , either high voltage powerline or public TV broadcast, refine this with power, tower:type, height tags or/and communication:* namespace tags, see wiki for more' WHERE building='hoogspanningsmast / openbare TV mast';
UPDATE planet_osm_polygon SET man_made='storage_tank', building='', fixme='Add the silo type and optionally building type, refine this with content=* see wiki for more information' WHERE building='silo, opslagtank';
UPDATE planet_osm_polygon SET man_made='groyne', building='', fixme='This can be either: golfbreker, strandhoofd of lage havendam' WHERE building='golfbreker, strandhoofd en lage havendam';
UPDATE planet_osm_polygon SET man_made='bridge', building='' WHERE building='overbrugging';
UPDATE planet_osm_polygon SET man_made='weir', fixme='Waterbouwkundig constructie: Doublecheck this tag carefully, it can be a weir, lock_gate, dam etc. check the wiki for the waterways key for more information. When in doubt, delete this object', building='' WHERE building='waterbouwkundig constructie';
EOF

# These are primarily if you hook up a bbox client script to it, not really interesting when all you want to do is export the built database to a file
cat /tmp/update.tags.sql | psql -U grb-data grb_api -h grb-db-0

if [ $? -eq 0 ]
then
  echo "Successfully Updated/mapped tags to their OSM counterparts"
else
  echo "Could not execute deletes/updates" >&2
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
cd ~

# address directly in the database using DBF database file, the tool will take care of all anomalities encountered (knw/Gbg)
# grb2osm/grb2osm.php -f /usr/local/src/grb/GRBgis_20001/Shapefile/TblGbgAdr20001B500.dbf,/usr/local/src/grb/GRBgis_10000/Shapefile/TblGbgAdr10000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblGbgAdr30000B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblGbgAdr40000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblGbgAdr70000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblKnwAdr30000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblKnwAdr70000B500.dbf,/usr/local/src/grb/GRBgis_20001/Shapefile/TblKnwAdr20001B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblKnwAdr40000B500.dbf

if [ $? -eq 0 ]
then
  echo "Successfully imported addresses into DB"
else
  echo "Could not address into DB" >&2
  exit 1
fi

echo ""
echo "Flush cache"
echo "==========="
 # flush redis cache
echo "flushall" | redis-cli 

