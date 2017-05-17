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

 echo "\n"
 echo "OGR2OSM"
 echo "======="
 rm -f "${filename}.osm"
 echo /usr/local/bin/ogr2osm/ogr2osm.py --idfile=ogr2osm.id --positive-id --saveid=ogr2osm.id "${filename}_parsed/${filename}.shp"
 /usr/local/bin/ogr2osm/ogr2osm.py --idfile=ogr2osm.id --positive-id --saveid=ogr2osm.id "${filename}_parsed/${filename}.shp"
 echo ""

# using sed to modify the data before import, it's a lot faster than queries but you need to be careful, those replacements have been carefully selected and tested in the beta site

# GBG
 if [ $entity == 'Gbg' ] 
    then
    echo "running gbg sed\n"
    # mapping the entities to the OSM equivalent
 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/shed/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gbg"/g' -i "${filename}.osm"
    # this line is needed for the tools to work so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

# we problably need to run the second sed for the first line only like this sed -i '1!b;s/test/blah/' file
# KNW
 if [ $entity == 'Knw' ] 
    then
    echo "running gbg sed\n"
    # mapping the entities to the OSM equivalent
 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/hoofdgebouw/house/g;s/bijgebouw/shed/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Knw"/g' -i "${filename}.osm"
    # this line is needed for osmosis to accept the OSM file so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

# GBA
 if [ $entity == 'Gba' ] 
    then
    echo "running gba sed\n"
    # mapping the entities to the OSM equivalent
 	sed -e 's/LBLTYPE/building/g;s/OIDN/source:geometry:oidn/g;s/UIDN/source:geometry:uidn/g;s/OPNDATUM/source:geometry:date/g;s/\"afdak\"/\"roof\"/g;s/\"ingezonken garagetoegang\"/\"garage3\"/g;s/\"verheven garagetoegang\"/\"garage4\"/g;s/tag k=\"TYPE\"\sv=\"[0-9]\+\"/tag k="source:geometry:entity" v="Gba"/g' -i "${filename}.osm"
    # this line is needed for osmosis to accept the OSM file we crated  so we need to add it to the osm file using sed to replace
 	sed -e 's/ visible="true"/ version="1" timestamp="1970-01-01T00:00:01Z" changeset="1" visible="true"/g' -i "${filename}.osm"
 fi

# addressing is done directly in the database now, it used to be done in the file but the tool has been updated since this
# echo "GRB2OSM"
# echo "======="
# # addressing vectors
# startname=${filename:0:3}
# restname=${filename:3}
# echo /usr/local/bin/grb2osm/grb2osm.php -f "${dirname}/Tbl${startname}Adr${restname}.dbf" -i "${filename}.osm" -o "${filename}_addressed.osm"
# /usr/local/bin/grb2osm/grb2osm.php -f "${dirname}/Tbl${startname}Adr${restname}.dbf" -i "${filename}.osm" -o "${filename}_addressed.osm"
#exit;
# echo -n $file
done

echo "OSMOSIS MERGE"
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

# postgresql work

 echo ""
 echo "IMPORT"
 echo "======"

/usr/bin/osm2pgsql --slim --create --cache 2000 --number-processes 2 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style --multi-geometry -d grb_api -U grb-data /datastore2/all_merged.osm -H grb-db-0

echo 'CREATE INDEX planet_osm_source_index_p ON planet_osm_polygon USING btree ("source:geometry:oidn" COLLATE pg_catalog."default");' | psql -U grb-data grb_api -h grb-db-0
echo 'CREATE INDEX planet_osm_source_ent_p ON planet_osm_polygon USING btree ("source:geometry:entity" COLLATE pg_catalog."default");' | psql -U grb-data grb_api -h grb-db-0
#echo 'CREATE INDEX planet_osm_source_index_o ON planet_osm_point USING btree ("source:geometry:oidn" COLLATE pg_catalog."default");' | psql -U grb-data grb
#echo 'CREATE INDEX planet_osm_source_index_n ON planet_osm_nodes USING btree ("source:geometry:oidn" COLLATE pg_catalog."default");' | psql -U grb-data grb
#echo 'CREATE INDEX planet_osm_source_index_l ON planet_osm_line USING btree ("source:geometry:oidn" COLLATE pg_catalog."default");' | psql -U grb-data grb
#echo 'CREATE INDEX planet_osm_source_index_r ON planet_osm_rels USING btree ("source:geometry:oidn" COLLATE pg_catalog."default");' | psql -U grb-data grb
#echo 'CREATE INDEX planet_osm_source_index_w ON planet_osm_ways USING btree ("source:geometry:oidn" COLLATE pg_catalog."default");' | psql -U grb-data grb

# setup source tag for all objects imported
echo "UPDATE planet_osm_polygon SET "source" = 'GRB';" | psql -U grb-data grb_api -h grb-db-0

# more indexes
echo 'CREATE INDEX planet_osm_src_index_p ON planet_osm_polygon USING btree ("source" COLLATE pg_catalog."default");' | psql -U grb-data grb_api -h grb-db-0

# use a query to update 'trap' as this word is a bit too generic and short to do with sed tricks
echo "UPDATE planet_osm_polygon set highway='steps', building='' where building='trap';" | psql -U grb-data grb_api -h grb-db-0

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


/usr/local/bin/grb2osm/grb2osm.php -f GRBgis_20001/Shapefile/TblGbgAdr20001.dbf,GRBgis_10000/Shapefile/TblGbgAdr10000.dbf,GRBgis_30000/Shapefile/TblGbgAdr30000.dbf,GRBgis_40000/Shapefile/TblGbgAdr40000.dbf,GRBgis_70000/Shapefile/TblGbgAdr70000.dbf

# address directly in the database using DBF database file, the tool will take care of all anomalities encountered
#/usr/local/bin/grb2osm/grb2osm.php -f GRBgis_20001/Shapefile/TblGbgAdr20001.dbf
#/usr/local/bin/grb2osm/grb2osm.php -f GRBgis_10000/Shapefile/TblGbgAdr10000.dbf
#/usr/local/bin/grb2osm/grb2osm.php -f GRBgis_30000/Shapefile/TblGbgAdr30000.dbf

echo ""
echo "Flush cache"
echo "==========="
 # flush redis cache
echo "flushall" | redis-cli 

