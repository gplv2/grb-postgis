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

# If you are low on diskspace, you can use fuse to mount the zips as device in user space
# fuse-zip -o ro ../php/files/GRBgis_40000.zip GRBgis_40000
# fusermount -u GRBgis_40000

#fuse-zip -o ro files/GRBgis_10000.zip GRBgis_10000
#fuse-zip -o ro files/GRBgis_20001.zip GRBgis_20001
#fuse-zip -o ro files/GRBgis_30000.zip GRBgis_30000
#fuse-zip -o ro files/GRBgis_40000.zip GRBgis_40000
#fuse-zip -o ro files/GRBgis_70000.zip GRBgis_70000
#fuse-zip -o ro files/GRBgis_04000.zip GRBgis_04000

for file in NAMUR/CONSTR_BATIEMPRISE.shp LIEGE/CONSTR_BATIEMPRISE.shp HAINAUT/CONSTR_BATIEMPRISE.shp LUXEMBOURG/CONSTR_BATIEMPRISE.shp BRABANT/CONSTR_BATIEMPRISE.shp

do
 echo "Processing $file"
 dirname=$(dirname "$file")
 filename=$(basename "$file")
 extension="${filename##*.}"
 filename="${filename%.*}"
 #entity=${filename:0:3} # Gba/Gbg

 # force PICC to Gbg logic since it's not the same as GRB but we only do building entities for now
 entity=Gbg

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
 if [ $entity == 'Gbg' ]
    then
    echo "${GREEN}running Picc/gbg sed${RESET}"
    # mapping the entities to the OSM equivalent
 	sed -e 's/NATUR_CODE/building/g;s/OBJECTID/source:geometry:oidn/g;s/DATE_MODIF/source:geometry:date/g;s/BAT/house/g;s/ANE/yes/g;s/BUI/yes/g;s/ANE/yes/g;s/tag k=\"CODE_WALTO\"\sv=\"([A-Z])\w+\"/tag k="source:geometry:entity" v="Picc"/g' -i "${filename}_${dirname}.osm"
    # this line is needed for the tools to work so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}_${dirname}.osm"
 fi

# 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/yes/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Knw"/g' -i "${filename}.osm"
#    # this line is needed for osmosis to accept the OSM file so we need to add it to the osm file using sed to replace
# 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
# 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/\"afdak\"/\"roof\"/g;s/\"ingezonken garagetoegang\"/\"garage3\"/g;s/\"verheven garagetoegang\"/\"garage4\"/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gba"/g' -i "${filename}.osm"
#    # this line is needed for osmosis to accept the OSM file we crated  so we need to add it to the osm file using sed to replace
# 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"

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

# postgresql work

echo ""
echo "${GREEN}IMPORT${RESET}"
echo "======"

if [ $TILESERVER == 'yes' ] ; then
    if [ -e "/datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm" ]; then
        #echo "${GREEN}Renumbering OSM data${RESET}"
        #osmosis --rx /datadisk2/out/all_merged.osm --rx /datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm --merge --wx /datadisk1/scratch/joined.osm
        echo "${GREEN}Renumbering GRB OSM file${RESET}"
        cat /datadisk2/out/all_picc_merged.osm | osm-renumber.pl > /datadisk1/scratch/all_picc_merged_renumbered.osm

        echo "${GREEN}Sorting GRB OSM file${RESET}"
        osmium sort -v --progress /datadisk1/scratch/all_picc_merged_renumbered.osm -o /datadisk1/scratch/all_picc_merged_renum_v2.osm

        echo "${GREEN}Merging GRB and OSM data${RESET}"
        osmosis --rx /datadisk1/scratch/all_picc_merged_renum_v2.osm --rx /datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm --merge --wx /datadisk2/out/joined.osm

        # /usr/bin/osm2pgsql --slim --create --cache 4000 --number-processes 3 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d ${DBDATA} -U ${DBUSER} /datadisk2/out/all_picc_merged.osm -H grb-db-0
        echo "${GREEN}Loading picc merged dataset in db: ${DBDATA}${RESET}"
        /usr/local/bin/osm2pgsql --slim --drop --create -m --cache ${CACHE} --number-processes ${THREADS} --hstore --multi-geometry --style /usr/local/src/be-carto/openstreetmap-carto.merge.style --tag-transform-script /usr/local/src/be-carto/openstreetmap-carto.merge.lua --multi-geometry -d ${DBDATA} -U ${DBUSER} -H 127.0.0.1 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace /datadisk2/out/joined.osm
    else
        echo "${RED}Could not find OSM filtered source file${RESET}" >&2
        exit 1
    fi
else
        /usr/local/bin/osm2pgsql --slim --drop --create -l --cache ${CACHE} --number-processes ${THREADS} --hstore --multi-geometry --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d ${DBDATA} -U ${DBUSER} -H 127.0.0.1 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace /datadisk2/out/all_picc_merged.osm

fi

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully imported PICC processed sources into PGSQL${RESET}"
else
    echo "${GREEN}Could not import merged PICC source files${RESET}" >&2
    exit 1
fi

echo "${GREEN}Creating additional indexes...${RESET}"

echo 'CREATE INDEX planet_osm_source_index_oidn ON planet_osm_polygon USING btree ("source:geometry:oidn" ) TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
#echo 'CREATE INDEX planet_osm_source_index_uidn ON planet_osm_polygon USING btree ("source:geometry:uidn" ) TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
echo 'CREATE INDEX planet_osm_source_index_ref ON planet_osm_polygon USING btree ("source:geometry:ref" ) TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
echo 'CREATE INDEX planet_osm_source_ent_p ON planet_osm_polygon USING btree ("source:geometry:entity" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d${DBDATA} -h 127.0.0.1
#echo 'CREATE INDEX planet_osm_source_index_o ON planet_osm_point USING btree ("source:geometry:oidn" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d grb
#echo 'CREATE INDEX planet_osm_source_index_n ON planet_osm_nodes USING btree ("source:geometry:oidn" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d grb
#echo 'CREATE INDEX planet_osm_source_index_l ON planet_osm_line USING btree ("source:geometry:oidn" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d grb
#echo 'CREATE INDEX planet_osm_source_index_r ON planet_osm_rels USING btree ("source:geometry:oidn" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d grb
#echo 'CREATE INDEX planet_osm_source_index_w ON planet_osm_ways USING btree ("source:geometry:oidn" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d grb

# setup source tag for all objects imported
# echo "UPDATE planet_osm_polygon SET "source" = 'GRB' WHERE building IS NOT NULL;" | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1

# more indexes
echo 'CREATE INDEX planet_osm_src_index_p ON planet_osm_polygon USING btree ("source" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1

# use a query to update 'trap' as this word is a bit too generic and short to do with sed tricks
echo "UPDATE planet_osm_polygon set highway='steps', building='' where building='trap';" | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1

echo "${GREEN}creating additional indexes...${RESET}"

cat > /tmp/create.indexes.sql << EOF
CREATE INDEX idx_planet_osm_line_nobridge ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE ((man_made <> ALL (ARRAY[''::text, '0'::text, 'no'::text])) OR man_made IS NOT NULL);
CREATE INDEX idx_pop_mm_null ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE (man_made IS NOT NULL);
CREATE INDEX idx_pop_no_bridge ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE (bridge <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_pop_hw_null ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE (highway IS NOT NULL);
CREATE INDEX idx_pop_no_hw ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE (highway <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_pop_no_b ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE (building <> ALL (ARRAY[''::text, '0'::text, 'no'::text]));
CREATE INDEX idx_pop_b_null ON planet_osm_polygon USING gist (way) TABLESPACE indexspace WHERE (building IS NOT NULL);
EOF

# These are primarily if you hook up a bbox client script to it, not really interesting when all you want to do is export the built database to a file
cat /tmp/create.indexes.sql | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully created indexes/updates${RESET}"
else
  echo "${RED}Could not execute indexing/updates${RESET}" >&2
  exit 1
fi

# change tags in DB
cat > /tmp/update.tags.sql << EOF
DELETE FROM planet_osm_polygon WHERE building IN ('garage3','pijler','rooster','zichtbare onderkeldering','cultuur-historisch monument','cabine','garage4','staketsel','gebouw afgezoomd met virtuele gevels','tunnelmond');
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
cat /tmp/update.tags.sql | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1

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
cd ~

# address directly in the database using DBF database file, the tool will take care of all anomalities encountered (knw/Gbg)
#php grb2osm/grb2osm.php -f /usr/local/src/grb/GRBgis_20001/Shapefile/TblGbgAdr20001B500.dbf,/usr/local/src/grb/GRBgis_10000/Shapefile/TblGbgAdr10000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblGbgAdr30000B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblGbgAdr40000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblGbgAdr70000B500.dbf,/usr/local/src/grb/GRBgis_30000/Shapefile/TblKnwAdr30000B500.dbf,/usr/local/src/grb/GRBgis_70000/Shapefile/TblKnwAdr70000B500.dbf,/usr/local/src/grb/GRBgis_20001/Shapefile/TblKnwAdr20001B500.dbf,/usr/local/src/grb/GRBgis_40000/Shapefile/TblKnwAdr40000B500.dbf

if [ $? -eq 0 ]
then
  echo "${GREEN}Successfully imported addresses into DB${RESET}"
else
  echo "${RED}Could not address into DB${RESET}" >&2
  exit 1
fi

echo "unmounting zip files"
# GRB
fusermount -u /usr/local/src/grb/NAMUR
fusermount -u /usr/local/src/grb/LIEGE
fusermount -u /usr/local/src/grb/BRABANT
fusermount -u /usr/local/src/grb/HAINAUT
fusermount -u /usr/local/src/grb/LUXEMBOURG

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

