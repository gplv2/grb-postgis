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
echo "${GREEN}IMPORT ALL${RESET}"
echo "======"

if [ $TILESERVER == 'yes' ] ; then
    if [ -e "/datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm" ]; then
        #echo "${GREEN}Renumbering OSM data${RESET}"
        #osmosis --rx /datadisk2/out/all_merged.osm --rx /datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm --merge --wx /datadisk1/scratch/joined.osm
        echo "${GREEN}Renumbering GRB OSM file${RESET}"
        cat /datadisk2/out/all_merged.osm | osm-renumber.pl > /datadisk1/scratch/all_merged_renumbered.osm

        echo "${GREEN}Sorting GRB OSM file${RESET}"
        osmium sort -v --progress /datadisk1/scratch/all_merged_renumbered.osm -o /datadisk1/scratch/all_merged_renum_v2.osm

        echo "${GREEN}Merging GRB and OSM data${RESET}"
        osmosis --rx /datadisk1/scratch/all_merged_renum_v2.osm --rx /datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm --merge --wx /datadisk2/out/joined.osm

        # /usr/bin/osm2pgsql --slim --create --cache 4000 --number-processes 3 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d ${DBDATA} -U ${DBUSER} /datadisk2/out/all_merged.osm -H grb-db-0
        echo "${GREEN}Loading merged dataset in db: ${DBDATA}${RESET}"
        /usr/local/bin/osm2pgsql --slim --drop --create -m --cache ${CACHE} --number-processes ${THREADS} --hstore --multi-geometry --style /usr/local/src/be-carto/openstreetmap-carto.merge.style --tag-transform-script /usr/local/src/be-carto/openstreetmap-carto.merge.lua --multi-geometry -d ${DBDATA} -U ${DBUSER} -H 127.0.0.1 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace /datadisk2/out/joined.osm
    else
        echo "${RED}Could not find OSM filtered source file${RESET}" >&2
        exit 1
    fi
else
	/usr/local/bin/osm2pgsql --slim --drop --create -l --cache ${CACHE} --number-processes ${THREADS} --hstore --multi-geometry --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d ${DBDATA} -U ${DBUSER} -H 127.0.0.1 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace /datadisk2/out/all_general_merged.osm

fi

if [ $? -eq 0 ]
then
    echo "${GREEN}Successfully imported processed sources into PGSQL${RESET}"
else
    echo "${GREEN}Could not import merged source files${RESET}" >&2
    exit 1
fi

echo "${GREEN}Creating additional indexes...${RESET}"

# for picc addressing index
echo 'CREATE INDEX planet_osm_osmid ON planet_osm_polygon USING btree ("osm_id") TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
#
echo 'CREATE INDEX planet_osm_source_index_oidn ON planet_osm_polygon USING btree ("source:geometry:oidn" ) TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
echo 'CREATE INDEX planet_osm_source_index_uidn ON planet_osm_polygon USING btree ("source:geometry:uidn" ) TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
echo 'CREATE INDEX planet_osm_source_index_ref ON planet_osm_polygon USING btree ("source:geometry:ref" ) TABLESPACE indexspace;' | psql -U ${DBUSER} -d ${DBDATA} -h 127.0.0.1
echo 'CREATE INDEX planet_osm_source_ent_p ON planet_osm_polygon USING btree ("source:geometry:entity" COLLATE pg_catalog."default") TABLESPACE indexspace;' | psql -U ${DBUSER} -d${DBDATA} -h 127.0.0.1
echo 'CREATE INDEX planet_osm_source_combined_p ON planet_osm_polygon USING btree ("source:geometry:entity" COLLATE pg_catalog."default", "source:geometry:oidn") TABLESPACE indexspace;' | psql -U ${DBUSER} -d${DBDATA} -h 127.0.0.1
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
DELETE FROM planet_osm_polygon WHERE highway='steps';
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
UPDATE planet_osm_polygon SET "source:geometry:entity"='Picc' WHERE tags->'GEOREF_ID' IS NOT NULL AND "source:geometry:entity" IS NULL;
UPDATE planet_osm_polygon SET building='commercial' WHERE building='MAG';
UPDATE planet_osm_polygon SET building='school' WHERE building='SCO';
UPDATE planet_osm_polygon SET building='farm_auxiliary' WHERE building='FRM';
UPDATE planet_osm_polygon SET building='industrial' WHERE building='IDS';
UPDATE planet_osm_polygon SET building='religious' WHERE building='LDC';
UPDATE planet_osm_polygon SET building='yes' WHERE building='CUL';
UPDATE planet_osm_polygon SET building='public' WHERE building='ADM';
UPDATE planet_osm_polygon SET building='school' WHERE building='SCF';
UPDATE planet_osm_polygon SET building='castle' WHERE building='CHT';
UPDATE planet_osm_polygon SET building='hospital' WHERE building='HOP';
UPDATE planet_osm_polygon SET building='school' WHERE building='SCS';
UPDATE planet_osm_polygon SET building='public' WHERE building='POL';
UPDATE planet_osm_polygon SET building='train_station' WHERE building='TRG';
UPDATE planet_osm_polygon SET building='university' WHERE building='SCU';
UPDATE planet_osm_polygon SET building='fire_station' WHERE building='POM';
UPDATE planet_osm_polygon SET building='yes' WHERE building='PRI';
UPDATE planet_osm_polygon SET building='yes' WHERE building='MDR';
UPDATE planet_osm_polygon SET building='government' WHERE building='HDV';
UPDATE planet_osm_polygon SET building='service' WHERE building='SDE';
UPDATE planet_osm_polygon SET building='yes' WHERE building='CEE';
UPDATE planet_osm_polygon SET building='yes' WHERE building='STS';
UPDATE planet_osm_polygon SET building='yes' WHERE building='Category 1';
UPDATE planet_osm_polygon SET building='yes' WHERE building='Category 2';
UPDATE planet_osm_polygon SET "source:geometry:date" = concat_ws('-',substring("source:geometry:date",1,4), substring("source:geometry:date",5,2), substring("source:geometry:date",7,2)) WHERE "source:geometry:entity"='Picc';
UPDATE planet_osm_polygon SET way=ST_centroid(way) WHERE man_made='mast';
UPDATE planet_osm_polygon SET osm_id=abs(osm_id) WHERE osm_id<0;
UPDATE planet_osm_polygon SET "addr:street" = upper(left("addr:street", 1)) || right("addr:street", -1) WHERE "addr:street" is not null AND "addr:street" <> upper(left("addr:street", 1)) || right("addr:street", -1) AND "addr:street" NOT IN ('von Asten-Straße','von-Dhaem-Strasse','von-Montigny-Straße','von-Orley-Straße','t Zand','be-MINE') AND position('''' IN "addr:street") <> 2;
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

echo ""
echo "${GREEN}Flush cache${RESET}"
echo ""
 # flush redis cache
echo "flushall" | redis-cli

