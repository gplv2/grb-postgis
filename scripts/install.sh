#!/bin/bash -e

# Screen colors using tput
RED=`tput setaf 1`
GREEN=`tput setaf 2`
RESET=`tput sgr0`
#ex: echo "${RED}red text ${GREEN}green text${RESET}"

# count cores
CORES=$(nproc --all || getconf _NPROCESSORS_ONLN)
THREADS=$((${CORES}-1))
DOUBLETHREADS=$((${CORES}*2))

# cache is free / 3
FREEMEM=$(free -m|awk '/^Mem:/{print $2}')
CACHE=$(($(free -m|awk '/^Mem:/{print $2}')/3))
PGEFFECTIVE=$(($(free -m|awk '/^Mem:/{print $2}')/2))

# RESOURCE_INDEX= grb-db-0
if [ -z "$RESOURCE_INDEX" ] ; then
    RESOURCE_INDEX=`hostname`
fi

CLOUD=google

echo "${GREEN}Gather metadata${RESET}"

if [ "${CLOUD}" = "google" ]; then
    # Gather metadata for the whole project, especially IP addresses
    IP=$(curl -s -H "Metadata-Flavor:Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/ip)
else
    IP=$(ifconfig eth0 | awk '/inet addr/ {gsub("addr:", "", $2); print $2}')
fi

if [ "${CLOUD}" = "google" ]; then
    # use python inventory script (ansible stuff)
    export GCE_INI_PATH=/usr/local/etc/gce.ini

    # get the project we belong to
    MY_PROJECT=$(<"/etc/myproject")

    IFS='-' read -r -a RES_ARRAY <<< "$RESOURCE_INDEX"

    for element in "${RES_ARRAY[@]}"
    do
        echo "meta: ${element}"
    done
fi

echo "${GREEN}Setting up configuration${RESET}"
PROJECT_NAME=grbapi
PROJECT_DIRECTORY=/var/www/${PROJECT_NAME}
DB=grb_api
USER=grb-data
DEPLOY_USER=glenn
PGPASS=/home/${DEPLOY_USER}/.pgpass
PGRC=/home/${DEPLOY_USER}/.psqlrc

# ini file for events/items DB access
DATA_DB=grb_temp
PASSWORD=str0ngDBp4ssw0rd
DB_CREDENTIALS=/home/${DEPLOY_USER}/dbconf.ini

DEBIAN_FRONTEND=noninteractive

# use fuse mount to save unzip space
SAVESPACE=yes

export DEBIAN_FRONTEND=$DEBIAN_FRONTEND
export RESOURCE_INDEX=$RESOURCE_INDEX
export IP=$IP

# Fix package problems
function silence_dpkg {
    echo "${GREEN}Silencing dpkg fancy stuff${RESET}"
    echo 'Dpkg::Progress-Fancy "0";' > /etc/apt/apt.conf.d/01progressbar

    echo "Trying to fix locales"
    echo "LC_ALL=en_US.UTF-8" >> /etc/environment

    # Generating locales...
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales
}

function fix_locales {
    echo "${GREEN}Fix locales${RESET}"
    # fix locales
    locale-gen "en_US.UTF-8"
    locale-gen "nl_BE.UTF-8"
    locale-gen "fr_BE.UTF-8"

    echo "nl_BE.UTF-8 fr_BE.UTF-8 UTF-8" >> /etc/locale.gen

    locale-gen
}

# Functions

function install_shapefiles {
    # install the shape files
    echo "${GREEN}Installing shapefiles${RESET}"
    cd /usr/local/src/openstreetmap-carto && scripts/get-shapefiles.py

    cd /usr/local/src/be-carto && ln -s /usr/local/src/openstreetmap-carto/data .
}

function install_tools {
    echo "${GREEN}Installing tools${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 protobuf-compiler libprotobuf-dev

    echo "Building protozero library"
    # Add the protozero libraries here since it was remove from osmium  see:  https://github.com/osmcode/libosmium/commit/bba631a51b3724327ed1a6a247d372da271b25cb
    cd /usr/local/src/ && git clone --recursive https://github.com/mapbox/protozero.git && cd /usr/local/src/protozero && mkdir build && cd build && cmake .. && make -j ${DOUBLECORES} && make install

    # we gonna need a few tools , start with GDAL (for ogr)
    echo "Building GDAL"
    #cd /usr/local/src/ && wget --quiet http://download.osgeo.org/gdal/2.2.0/gdal-2.2.0.tar.gz && tar -xzvf gdal-2.2.0.tar.gz && cd gdal-2.2.0 && ./configure && make -j ${DOUBLECORES} && make install && ldconfig
    cd /usr/local/src/ && wget --quiet https://download.osgeo.org/gdal/2.2.4/gdal-2.2.4.tar.gz && tar -xzvf gdal-2.2.4.tar.gz && cd gdal-2.2.4 && ./configure && make -j ${THREADS} && make install && ldconfig

    echo "Building osm2pgsql"
    cd /usr/local/src/ && git clone --recursive git://github.com/openstreetmap/osm2pgsql.git && cd /usr/local/src/osm2pgsql && mkdir build && cd build && cmake .. && make -j ${CORES} && make install
    echo "Building libosmium standalone library and osmium tool"
    cd /usr/local/src/ && git clone --recursive https://github.com/osmcode/libosmium.git && git clone https://github.com/osmcode/osmium-tool.git && cd /usr/local/src/libosmium && mkdir build && cd build && cmake .. && make -j ${CORES} && make install && cd /usr/local/src/osmium-tool && mkdir build && cd build && cmake .. && make -j ${CORES} && make install

    # building osmium-tool
    #    git clone https://github.com/osmcode/libosmium.git
    #    git clone https://github.com/osmcode/osmium-tool.git
    #    cd osmium-tool/
    #    mkdir build
    #    cd build
    #    cmake ..
    #    make

    #.configure && make -j 6 && make install && ldconfig

    # ogr2osm from Peter Norman (use a fork because there is a performance issue)
    #cd /usr/local/bin && git clone --recursive git://github.com/pnorman/ogr2osm.git
    # ogr2osm from Peter Norman
    cd /usr/local/bin && git clone --recursive git://github.com/pnorman/ogr2osm.git
    # need to add this directory to PATH
    export PATH=$PATH:/usr/local/bin/ogr2osm
    # carto CSS for building our custom OSM DB
    cd /usr/local/src/ && git clone https://github.com/gravitystorm/openstreetmap-carto.git

    # carto for BELGIUM tiles
    cd /usr/local/src/ && git clone https://github.com/jbelien/openstreetmap-carto-be.git be-carto

    #sed -i.save "s|dbname:".*"$|dbname: \"${DATA_DB}\"|" /usr/local/src/be-carto/project.mml
    sed -i.save "s|dbname:".*"$|dbname: \"${DATA_DB}\"\n    host: 127.0.0.1\n    user: \"${USER}\"\n    password: \"${PASSWORD}\"|" /usr/local/src/be-carto/project.mml

    cd /usr/local/src/be-carto && python -c 'import sys, yaml, json; json.dump(yaml.safe_load(sys.stdin), sys.stdout, indent=4, separators=(",", ": "))' < project.mml > project.json.mml
    cd /usr/local/src/be-carto && carto -a "3.0.0" project.json.mml > mapnik.xml

    # copy modified style sheet (wonder if I still need the rest of the source of cartocss (seems to work like this)
    cp /usr/local/src/openstreetmap-carto/openstreetmap-carto.style /usr/local/src/openstreetmap-carto/openstreetmap-carto-orig.style
    #
    cp /tmp/configs/openstreetmap-carto.style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style
    cp /tmp/configs/openstreetmap-carto-3d.style /usr/local/src/openstreetmap-carto/

    # merge styles
    cp /tmp/configs/openstreetmap-carto.merge.* /usr/local/src/be-carto/

    echo "${GREEN}Installing small tools in /usr/local/bin/${RESET}"
    cp /tmp/osm-renumber.pl /usr/local/bin/
    chmod +x /usr/local/bin/osm-renumber.pl
}

function install_compile_packages {
    echo "${GREEN}Installing Compilation tools${RESET}"
    # we need to prepare a partial tilesever setup so we can load belgium in a postGIS database , there might be some duplicate packages with the rest of this script
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 libboost-all-dev git-core tar gzip unzip wget bzip2 build-essential autoconf libtool libgeos-dev libgeos++-dev libpq-dev libproj-dev libprotobuf-c0-dev libxml2-dev protobuf-c-compiler libfreetype6-dev libpng12-dev libtiff5-dev libicu-dev libcairo-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont liblua5.1-dev libgeotiff-epsg fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted python-yaml make cmake g++ libboost-dev libboost-system-dev libboost-filesystem-dev libexpat1-dev zlib1g-dev libbz2-dev libpq-dev liblua5.2-dev osmctools libprotozero-dev libutfcpp-dev rapidjson-dev pandoc clang-tidy cppcheck iwyu recode

    # postgis is already present, so skip that step, but nodejs is not
    curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -

    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 nodejs
    # these libraries are needed to compile osm2pgsql from source
}

function install_mapnik {
    echo "${GREEN}Installing Mapnik${RESET}"
    # install mapnik, this needs to be run after installing packages from install_compile_packages function
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 libmapnik-dev mapnik-utils python-mapnik
}

function install_modtile {
    echo "${GREEN}Installing mod_tile${RESET}"

    #mkdir /usr/local/src/grb
    #chown -R ${DEPLOY_USER}:${DEPLOY_USER} /usr/local/src/grb/mapnik

    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb/ && git clone -b switch2osm git://github.com/SomeoneElseOSM/mod_tile.git && cd /usr/local/src/grb/mod_tile && ./autogen.sh && ./configure && make -j ${CORES}"

    if [ $? -eq 0 ]
        then
        echo "Successfully compiled modtile sources, going to install it"
        cd /usr/local/src/grb/mod_tile && make install && make install-mod_tile
        ldconfig
    fi
}

function install_carto_compiler {
    echo "${GREEN}installing carto compiler${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont
    npm install -g carto
    carto -v
}

# /usr/local/src/openstreetmap-carto/openstreetmap-carto-orig.style
function preprocess_carto {
    echo "${GREEN}Preprocess carto${RESET}"
    cp /tmp/configs/project.mml /usr/local/src/openstreetmap-carto/
    cd /usr/local/src/openstreetmap-carto && carto project.mml > mapnik.xml
    #cp /usr/local/src/grb/mapnik.xml /usr/local/src/openstreetmap-carto
}

function config_modtile {
    echo "${GREEN}Config mod_tile${RESET}"
    # /usr/local/src/grb/mod_tile/mod_tile.conf
    #cp /usr/local/src/grb/mod_tile/mod_tile.conf /etc/apache2/conf-available/
    cp /tmp/configs/mod_tile.conf /etc/apache2/conf-available/mod_tile.conf
    cd /etc/apache2/conf-enabled && ln -s /etc/apache2/conf-available/mod_tile.conf .

    sed -i "s/Listen 80/Listen 81/" /etc/apache2/ports.conf
    sed -i "s/Listen 443/#Listen 443 # by provisioner/" /etc/apache2/ports.conf
}

function config_renderd {
    echo "${GREEN}Config renderd${RESET}"
    cd /etc/apache2/

    cp /tmp/configs/apache2.conf /etc/apache2/

    cp /tmp/configs/000-default.conf /etc/apache2/sites-available/
    cp /tmp/configs/renderd.conf /usr/local/etc/renderd.conf

    sed -i -r "s|num_threads=".*"$|num_threads=${THREADS}|" /usr/local/etc/renderd.conf

    #cd /etc/apache2/conf-enabled && ln -s /etc/apache2/conf-available/mod_tile.conf .

    mkdir /var/lib/mod_tile /var/run/renderd

    chown -R www-data:www-data /var/lib/mod_tile

    /etc/init.d/apache2 restart

    echo  "installing renderd service"
    # change running user
    sed -i "s/RUNASUSER=renderaccount/RUNASUSER=www-data/" /usr/local/src/grb/mod_tile/debian/renderd.init
    cp /usr/local/src/grb/mod_tile/debian/renderd.init /etc/init.d/renderd
    chmod u+x /etc/init.d/renderd
    cp /usr/local/src/grb/mod_tile/debian/renderd.service /lib/systemd/system/

    /bin/systemctl enable renderd

    echo  "Installing render list tool"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && git clone https://github.com/gplv2/render_list_geo.pl.git render_list"
}

function install_renderd_service {
    echo "${GREEN}Installing renderd${RESET}"
    cp /usr/local/src/grb/mod_tile/debian/renderd.init /etc/init.d/renderd
    chmod u+x /etc/init.d/renderd
    cp /usr/local/src/grb/mod_tile/debian/renderd.service /lib/systemd/system/

    echo  "starting renderd service"
    [ -x /etc/init.d/renderd ] && /etc/init.d/renderd start

    sleep 1
    echo  "Reload"
    systemctl daemon-reload
    sleep 1
}

function install_nginx_tilecache {
    echo "${GREEN}configuring nginx tile cache service${RESET}"
    sleep 1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 nginx
    cp /tmp/configs/upstream.conf /etc/nginx/conf.d/
    cp /tmp/configs/nginx_default.conf /etc/nginx/sites-available/default

    /etc/init.d/nginx restart
}

function install_letsencrypt {
    echo "${GREEN}Installing letsencrypt${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 letsencrypt

    cd /etc/ && tar -xzvf /tmp/configs/lets.tgz

    # TEMP DISABLE< ENABLE WHEN DEPLOYING FRESH !
    #letsencrypt --renew-by-default -a webroot --webroot-path /var/www/html --email glenn@bitless.be --text --agree-tos -d tiles.grbosm.site auth
}

function install_test_site {
    echo "${GREEN}Installing test website${RESET}"
    cd /var/www/ && tar -xzvf /tmp/configs/website.tgz
}

function enable_ssl {
    echo "${GREEN}Building openssl${RESET}"
    curl https://www.openssl.org/source/openssl-1.0.2n.tar.gz | tar xz && cd openssl-1.0.2n && sudo ./config no-ssl2 no-ssl3 && sudo make -j ${CORES} TARGET=linux2628 USE_PCRE=1 USE_OPENSSL=1 USE_ZLIB=1 SSL_LIB=/usr/local/ssl/lib SSL_INC=/usr/local/ssl/include/ && make install && ldconfig

    cd /usr/local/src/ && git clone http://git.haproxy.org/git/haproxy-1.7.git

    echo "${GREEN}Building haproxy${RESET}"
    cd haproxy-1.7 && make -j ${DOUBLECORES} TARGET=linux2628 USE_PCRE=1 USE_OPENSSL=1 USE_ZLIB=1 SSL_LIB=/usr/local/ssl/lib SSL_INC=/usr/local/ssl/include/

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 haproxy

    /etc/init.d/haproxy stop

    cp haproxy /usr/sbin/

    echo "haproxy hold" | sudo dpkg --set-selections

    mkdir /etc/haproxy/certs.d

    cp /tmp/configs/haproxy.cfg /etc/haproxy/haproxy.cfg

    echo "Create dhparam file..."
    /usr/local/ssl/bin/openssl dhparam -dsaparam -out /etc/haproxy/dhparam.pem 4096
    # Skip this 4096 one for the time being, takes a long time on small servers!
    # openssl dhparam -dsaparam -out /etc/nginx/dhparam.pem 2048

    cat /etc/letsencrypt/live/tiles.grbosm.site/privkey.pem /etc/letsencrypt/live/tiles.grbosm.site/cert.pem /etc/letsencrypt/live/tiles.grbosm.site/chain.pem /etc/haproxy/dhparam.pem > /etc/haproxy/certs.d/tiles.pem

    # softlink the default cert
    cd /etc/haproxy/ && ln -s certs.d/tiles.pem default.pem

    echo "${GREEN}Starting haproxy${RESET}"
    /etc/init.d/haproxy start
}

function load_osm_data {
    echo "${GREEN}Loading OSM data${RESET}"
    # the data should be present in /usr/loca/src/grb workdir
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://download.geofabrik.de/europe/belgium-latest.osm.pbf"
    # make use of the pgsql tablespace setup having the indexes on a second disk, this speeds up import significantly
    #      --tablespace-main-data    tablespace for main tables
    #      --tablespace-main-index   tablespace for main table indexes
    #      --tablespace-slim-data    tablespace for slim mode tables
    #      --tablespace-slim-index   tablespace for slim mode indexes

    # filter out OSM buildings
    echo "${GREEN}Converting .pbf to .o5m${RESET}"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && osmconvert --out-o5m belgium-latest.osm.pbf > /datadisk2/out/belgium-latest.o5m"
    echo "${GREEN}Filtering buildings from .o5m${RESET}"
    su - ${DEPLOY_USER} -c 'cd /usr/local/src/grb && osmfilter /datadisk2/out/belgium-latest.o5m --drop="building=" -o=/usr/local/src/grb/belgium-latest-nobuildings.o5m'
    echo "${GREEN}Converting .o5m to .osm${RESET} (for osmosis)"
    su - ${DEPLOY_USER} -c 'cd /usr/local/src/grb && osmconvert --out-osm belgium-latest-nobuildings.o5m > /datadisk2/out/belgium-latest-nobuildings.osm'

    echo "${GREEN}Sorting OSM file${RESET}"
    su - ${DEPLOY_USER} -c "osmium sort -v --progress /datadisk2/out/belgium-latest-nobuildings.osm -o /datadisk1/scratch/belgium-latest-nobuildings-renumbered.osm"

    echo "${GREEN}Renumbering sorted file${RESET}"
    su - ${DEPLOY_USER} -c "cat /datadisk1/scratch/belgium-latest-nobuildings-renumbered.osm  | osm-renumber.pl > /datadisk2/out/belgium-latest-nobuildings-renum.osm"

    echo "${GREEN}Sorting OSM file${RESET}"
    su - ${DEPLOY_USER} -c "osmium sort -v --progress /datadisk2/out/belgium-latest-nobuildings-renum.osm -o /datadisk1/scratch/belgium-latest-nobuildings-renum_v2.osm"

    # cat /datadisk2/out/belgium-latest-nobuildings-renumbered.osm  | ./osm-renumber.pl > /datadisk1/scratch/belgium-latest-nobuildings-renum.osm
    # osmium renumber -v --progress /datadisk2/out/belgium-latest-nobuildings-sorted.osm -o /datadisk2/out/belgium-latest-nobuildings-renumbered.osm
    # osmium sort -v --progress /datadisk2/out/belgium-latest-nobuildings.osm /datadisk2/out/belgium-latest-nobuildings-sorted.osm

    echo "${GREEN}Loading dataset in db: ${DATA_DB} ${RESET}"
    # since we use a good fat machine with 4 processeors, lets use 3 for osm2pgsql and keep one for the database
    sudo su - $DEPLOY_USER -c "/usr/local/bin/osm2pgsql --slim --create -m --cache ${CACHE} --unlogged -G --number-processes ${THREADS} --hstore --tag-transform-script /usr/local/src/be-carto/openstreetmap-carto.lua --style /usr/local/src/be-carto/openstreetmap-carto.style -d ${DATA_DB} -U ${USER} /usr/local/src/grb/belgium-latest.osm.pbf -H 127.0.0.1 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace"
}

function create_osm_indexes {
    echo "${GREEN}Creating data indexes${RESET}"
    # now inxdex extra
    su - postgres -c "cat /tmp/tile_indexes.sql | psql -d ${DATA_DB}"

    echo  "Stopping renderd service (close postgres connections)"
    [ -x /etc/init.d/renderd ] && /etc/init.d/renderd stop

    echo "${GREEN}Preparing pre-move data + indexes${RESET}"
    # premove to default to avoid errors
    MOVESQL="SELECT ' ALTER TABLE ' || schemaname || '.' || tablename || ' SET TABLESPACE pg_default;' FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');"

    # create alter list
    su - postgres -c "psql -qAtX -d ${DATA_DB} -c \"${MOVESQL}\" > /tmp/alter.pre.ts.sql 2>/dev/null"

    su - postgres -c "cat /tmp/alter.pre.ts.sql | psql -d ${DATA_DB}"

    echo "${GREEN}Moving data + indexes to tablespace${RESET}"
    # move those indexes for grb_temp
    sed -i "s/${DB}/${DATA_DB}/" /tmp/alter.ts.sql

    su - postgres -c "cat /tmp/alter.ts.sql | psql"

    # restorey
    sed -i "s/${DATA_DB}/${DB}/" /tmp/alter.ts.sql

    [ -x /etc/init.d/renderd ] && /etc/init.d/renderd start
}

function transform_srid {
    echo "${GREEN}Transforming data${RESET}"
    # now inxdex extra
    # this shoul not be needed anymore when importing with osm2pgsql -m flag instead of -l
    su - postgres -c "cat /tmp/transform_db.sql | psql -d ${DATA_DB}"
}

function process_source_data {
    echo "${GREEN}Process source data${RESET}"
    # call external script
    chmod +x /tmp/process_source.sh
    su - ${DEPLOY_USER} -c "nice /tmp/process_source.sh"

    # now move all the indexes to the second disk for speed (the tables will probably be ok but the indexes not (no default ts)
    #[ -x /etc/init.d/renderd ] && /etc/init.d/renderd stop
    #su - postgres -c "cat /tmp/alter.ts.sql | psql"
    #[ -x /etc/init.d/renderd ] && /etc/init.d/renderd start
}

function process_3d_source_data {
    echo "${GREEN}Process 3D source data${RESET}"
    # call external script
    chmod +x /tmp/process_3D_source.sh
    su - ${DEPLOY_USER} -c "/tmp/process_3D_source.sh"

    [ -x /etc/init.d/renderd ] && /etc/init.d/renderd stop
    # now move all the indexes to the second disk for speed (the tables will probably be ok but the indexes not (no default ts)
    su - postgres -c "cat /tmp/alter.ts.sql | psql"
    [ -x /etc/init.d/renderd ] && /etc/init.d/renderd start
}


function create_db_ini_file {
    echo "${GREEN}Checking DB ini${RESET}"
    if [ ! -e "${DB_CREDENTIALS}" ]; then
        echo "create DB INI"
        echo "user     = ${USER}" > $DB_CREDENTIALS
        echo "database = ${DATA_DB}" >> $DB_CREDENTIALS
        #echo "host     = grb-db-0" >> $DB_CREDENTIALS
        echo "host     = 127.0.0.1" >> $DB_CREDENTIALS
        echo "password = ${PASSWORD}" >> $DB_CREDENTIALS
    fi
}

function create_pgpass {
    echo "${GREEN}Checking pgpass${RESET}"
    if [ ! -e "${PGPASS}" ]; then
        echo "create ${PGPASS}"
        echo "localhost:5432:${DB}:${USER}:${PASSWORD}" > $PGPASS
        echo "localhost:5432:${DATA_DB}:${USER}:${PASSWORD}" >> $PGPASS
        echo "127.0.0.1:5432:${DB}:${USER}:${PASSWORD}" >> $PGPASS
        echo "127.0.0.1:5432:${DATA_DB}:${USER}:${PASSWORD}" >> $PGPASS
        PERMS=$(stat -c "%a" ${PGPASS})
        if [ ! "${PERMS}" = "0600" ]; then
            chmod 0600 ${PGPASS}
        fi
        cp /tmp/rcfiles/psqlrc $PGRC

        chown -R ${DEPLOY_USER}:${DEPLOY_USER} $PGPASS $PGRC
    fi
}

function prepare_source_data {
    echo "${GREEN}Downloading source data${RESET}"
    # downloading GRB data from private CDN or direct source

    echo "${GREEN}downloading GRB extracts (mirror)${RESET}"
    # wget seems to exhibit a bug in combination with running from terraform, quiet fixes that
    # this is using my own mirror of the files as the download process with AGIV doesn't really work with automated downloads
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_10000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_20001B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_30000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_40000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_70000B500.zip"

    echo "${GREEN}downloading GRB 3D extracts (mirror)${RESET}"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/3D_GRB_04000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/3D_GRB_30000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/3D_GRB_20001B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/3D_GRB_40000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/3D_GRB_70000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/3D_GRB_10000B500.zip"

    if [ "${SAVESPACE}" = "yes" ] || [ -z "${SAVESPACE}" ] ; then
        # If you are low on diskspace, you can use fuse to mount the zips as device in user space
        cd /usr/local/src/grb
        mkdir GRBgis_10000 GRBgis_20001 GRBgis_30000 GRBgis_40000 GRBgis_70000
        chown ${DEPLOY_USER}:${DEPLOY_USER} GRBgis_10000 GRBgis_20001 GRBgis_30000 GRBgis_40000 GRBgis_70000

        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/GRBgis_20171105_10000B500.zip GRBgis_10000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/GRBgis_20171105_20001B500.zip GRBgis_20001"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/GRBgis_20171105_30000B500.zip GRBgis_30000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/GRBgis_20171105_40000B500.zip GRBgis_40000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/GRBgis_20171105_70000B500.zip GRBgis_70000"

        mkdir 3D_GRB_04000 3D_GRB_30000 3D_GRB_20001 3D_GRB_40000 3D_GRB_70000 3D_GRB_10000
        chown ${DEPLOY_USER}:${DEPLOY_USER} 3D_GRB_04000 3D_GRB_30000 3D_GRB_20001 3D_GRB_40000 3D_GRB_70000 3D_GRB_10000

        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/3D_GRB_04000B500.zip 3D_GRB_04000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/3D_GRB_30000B500.zip 3D_GRB_30000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/3D_GRB_20001B500.zip 3D_GRB_20001"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/3D_GRB_40000B500.zip 3D_GRB_40000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/3D_GRB_70000B500.zip 3D_GRB_70000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb ;fuse-zip -o ro /usr/local/src/grb/3D_GRB_10000B500.zip 3D_GRB_10000"

        # unmounting :

        #fusermount -u /usr/local/grb/GRBgis_10000
        #fusermount -u /usr/local/grb/GRBgis_20001
        #fusermount -u /usr/local/grb/GRBgis_30000
        #fusermount -u /usr/local/grb/GRBgis_40000
        #fusermount -u /usr/local/grb/GRBgis_70000

        #fusermount -u /usr/local/grb/3D_GRB_04000
        #fusermount -u /usr/local/grb/3D_GRB_30000
        #fusermount -u /usr/local/grb/3D_GRB_20001
        #fusermount -u /usr/local/grb/3D_GRB_40000
        #fusermount -u /usr/local/grb/3D_GRB_70000
        #fusermount -u /usr/local/grb/3D_GRB_10000
        echo "${GREEN}Done mounting zip sources${RESET}"
    else
        echo "${GREEN}extracting GRB data...${RESET}"
        # unpacking all provinces data
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_10000B500.zip -d GRBgis_10000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_20001B500.zip -d GRBgis_20001"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_30000B500.zip -d GRBgis_30000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_40000B500.zip -d GRBgis_40000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_70000B500.zip -d GRBgis_70000"
        # GRBgis_10000 GRBgis_20001 GRBgis_30000 GRBgis_40000 GRBgis_70000

        echo "${GREEN}extracting 3D data...${RESET}"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_04000B500.zip -d 3D_GRB_04000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_30000B500.zip -d 3D_GRB_30000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_20001B500.zip -d 3D_GRB_20001"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_40000B500.zip -d 3D_GRB_40000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_70000B500.zip -d 3D_GRB_70000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_10000B500.zip -d 3D_GRB_10000"
        # 3D_GRB_04000 3D_GRB_30000 3D_GRB_20001 3D_GRB_40000 3D_GRB_70000 3D_GRB_10000
        echo "${GREEN}Done extracting and preparing sources${RESET}"
    fi
}

# Create an aliases file so we can use short commands to navigate a project
function create_bash_alias {
    echo "${GREEN}Setting up bash aliases${RESET}"
    # the db alias : psql -h 127.0.0.1 -d grb-temp -U ${USER}
cat > /root/.bash_aliases << EOF
alias psqlc='psql -h 127.0.0.1 -d ${DATA_DB} -U ${USER}'
alias home='cd ${PROJECT_DIRECTORY}'
EOF
}

function install_grb_sources {
    echo "${GREEN}Install GRB sources${RESET}"
    # https://github.com/gplv2/grb2pgsql.git
    # https://github.com/gplv2/grb2osm.git
    # https://github.com/gplv2/grbtool.git

    #su - ${DEPLOY_USER} -c "git clone git@github.com:gplv2/grbtool.git grbtool"
    #su - ${DEPLOY_USER} -c "git clone git@github.com:gplv2/grb2osm.git grb2osm"
    su - ${DEPLOY_USER} -c "git clone https://github.com/gplv2/grbtool.git grbtool"
    su - ${DEPLOY_USER} -c "git clone https://github.com/gplv2/grb2osm.git grb2osm"
    su - ${DEPLOY_USER} -c "cd grb2osm && composer install"
    su - ${DEPLOY_USER} -c "chmod +x /home/${DEPLOY_USER}/grb2osm/grb2osm.php"

    # with submodules
    su - ${DEPLOY_USER} -c "git clone --recursive https://github.com/gplv2/grb2pgsql.git grb2pgsql"
    #su - ${DEPLOY_USER} -c "cd grb2pgsql && git submodule init"
    #su - ${DEPLOY_USER} -c "cd grb2pgsql && git submodule update --recursive --remote"
}

function make_grb_dirs {
    echo "${GREEN}Creating dirs${RESET}"
    CREATEDIRS="/usr/local/src/grb /datadisk2/out"

    for dir in $CREATEDIRS
    do
        if [ ! -d "$dir" ]; then
            mkdir $dir

            if [ $? -eq 0 ]
            then
                echo "Created directory $dir"
            else
                echo "Could not create $dir" >&2
                exit 1
            fi
            chown -R ${DEPLOY_USER}:${DEPLOY_USER} $dir
        fi

#        PERMS=$(stat -c "%a" $dir)
#        if [ ! "${PERMS}" = "0700" ]; then
#            chmod 0700 /root/.ssh
#        fi
    done
}

function create_deploy_user {
    echo "${GREEN}Creating deploy user${RESET}"
    if [ ! -d "/home/${DEPLOY_USER}" ]; then
        # Adding a deploy user
        PASS=YgjwiWbc2UWG.
        SPASS=`openssl passwd -1 $PASS`
        /usr/sbin/useradd -p $SPASS --create-home -s /bin/bash -G www-data $DEPLOY_USER
    fi
}

function install_os_packages {
    echo "${GREEN}Sort OS packages out${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq -y -o=Dpkg::Use-Pty=0

    # remove mdadm annoying package with extended wait
    DEBIAN_FRONTEND=noninteractive apt-get remove -qq -y -o=Dpkg::Use-Pty=0 mdadm

    DEBIAN_FRONTEND=noninteractive apt-get upgrade -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -f -o Dpkg::Use-Pty=0
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -f -o Dpkg::Use-Pty=0

    [ -r /etc/lsb-release ] && . /etc/lsb-release

    if [ -z "$DISTRIB_RELEASE" ] && [ -x /usr/bin/lsb_release ]; then
        # Fall back to using the very slow lsb_release utility
        DISTRIB_RELEASE=$(lsb_release -s -r)
        DISTRIB_CODENAME=$(lsb_release -s -c)
    fi

    echo "Preparing for ubuntu %s - %s" "$DISTRIB_RELEASE" "$DISTRIB_CODENAME"

    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 zip unzip htop aeson-pretty ccze python3 python3-crypto python3-libcloud jq git rsync dsh monit tree monit postgresql-client-9.5 python-crypto python-libcloud ntpdate redis-server fuse-zip


    if [ ! -e "/etc/projectdata.json" ]; then
        echo "${GREEN}Provisioning GCE(vm): ${RES_ARRAY[1]} / ${RES_ARRAY[2]}${RESET}"
        echo "Install packages ..."
        # Download helper scripts to create a configuration file (for google cloud)
        if [ "${CLOUD}" = "google" ]; then
            cd /usr/local/etc/
            wget --quiet https://raw.githubusercontent.com/gplv2/ansible/devel/contrib/inventory/gce.ini

            cd /usr/local/bin/
            wget --quiet https://raw.githubusercontent.com/gplv2/ansible/devel/contrib/inventory/gce.py
            chmod +x /usr/local/bin/gce.py

            # replace project id, ex: gce_project_id = api-project-37604919139
            sed -i "s/gce_project_id = /gce_project_id = ${MY_PROJECT}/" $GCE_INI_PATH
            # gce_project_id =

            # Now run the script and pipe through a prettyfier so we can read it
            # We are making an exception here and store this in /etc as it is static and system wide, set once
            /usr/local/bin/gce.py --list | aeson-pretty > /etc/projectdata.json
            # Now the project information is available and you can find out the other nodes (using tags for example)
        fi
    fi
}

function install_selected_packages {
    # for all servers
    echo "${GREEN}Install specific packages ...${RESET}"

    if [ "${RES_ARRAY[1]}" = "www" ]; then
        if [ "$DISTRIB_RELEASE" = "16.04" ]; then
            echo "Install $DISTRIB_RELEASE packages ..."
            DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties curl cmake openssl libssl-dev phpunit php7.0 php-dev php-pear pkg-config pkgconf pkg-php-tools g++ make memcached libmemcached-dev python3-software-properties php-memcached php-memcache php-cli php-mbstring cmake php-pgsql node-uglify

            if [ ! -e "/home/${DEPLOY_USER}/.hushlogin" ]; then
                touch /home/${DEPLOY_USER}/.hushlogin
                chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.hushlogin
            fi
        fi

        if [ "$DISTRIB_RELEASE" = "16.04" ]; then
            if [ ! -e "/usr/local/bin/composer" ]; then
                echo "Updating global Composer ..."
                curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
            fi
        fi
    fi


    if [ "${RES_ARRAY[1]}" = "db" ]; then
        if [ "$DISTRIB_RELEASE" = "16.04" ]; then
            echo "Install $DISTRIB_RELEASE packages ..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties curl cmake openssl libssl-dev phpunit php7.0 php-dev php-pear pkg-config pkgconf pkg-php-tools g++ make memcached libmemcached-dev python3-software-properties php-memcached php-memcache php-cli php-mbstring cmake php-pgsql osmosis

            if [ ! -e "/home/${DEPLOY_USER}/.hushlogin" ]; then
                touch /home/${DEPLOY_USER}/.hushlogin
                chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.hushlogin
            fi
        fi

        if [ "$DISTRIB_RELEASE" = "16.04" ]; then
            if [ ! -e "/usr/local/bin/composer" ]; then
                echo "Updating global Composer ..."
                curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
            fi
        fi
    fi
}

function install_configure_postgres {
    # DB server
    if [ "${RES_ARRAY[1]}" = "db" ]; then
        # test for postgres install
        if [ $(dpkg-query -W -f='${Status}' postgresql 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
            echo "Setting up shared mem"
            chmod +x /usr/local/bin/shmsetup.sh
            /usr/local/bin/shmsetup.sh >> /etc/sysctl.conf

            echo "${GREEN}Installing postgres DB server ...${RESET}"
            # DISTRIB_RELEASE=16.04
            if [ "$DISTRIB_RELEASE" = "16.04" ]; then
                echo "Install $DISTRIB_RELEASE packages ..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 postgresql pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties php-memcached php-memcache libmsgpack-dev curl php-cli php-mbstring cmake php-pgsql pgbouncer postgresql-contrib postgis postgresql-9.5-postgis-2.2 libpq-dev libproj-dev python-geolinks python-gdal
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 php-msgpack
            fi

            # enable listen
            if [ -e "/etc/postgresql/9.5/main/postgresql.conf" ]; then
                echo "Enable listening on all interfaces"
                sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/9.5/main/postgresql.conf
                echo "Configuring shared buffers"
                page_size=`getconf PAGE_SIZE`
                phys_pages=`getconf _PHYS_PAGES`

                if [ -z "phys_pages" ]; then
                    echo "Error:  cannot determine page size"
                else
                    shmall=`expr $phys_pages / 2`
                    shmmax=`expr $shmall \* $page_size`
                    echo "Maximum shared segment size in bytes: ${shmmax}"
                    # converting this to a safe GB value for postgres
                    sed -i -r "s|#?effective_cache_size =".*"$|effective_cache_size = ${PGEFFECTIVE}MB|" /etc/postgresql/9.5/main/postgresql.conf

                    postgres_shared=`expr $shmmax / 1024 / 1024 / 1000`
                    echo "Postgres shared buffer size in GB: ${postgres_shared}"
                    echo "Configuring memory settings"
                    sed -i "s/shared_buffers = 128MB/shared_buffers = ${postgres_shared}GB/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#work_mem = 4MB/work_mem = 8MB/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = 2048MB/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#max_files_per_process = 1000/max_files_per_process = 10000/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#full_page_writes = on/full_page_writes = on/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#fsync = on/fsync = off/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#synchronous_commit = on/synchronous_commit = off/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#wal_level = minimal/wal_level = minimal/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#temp_buffers = 8MB/temp_buffers = 32MB/" /etc/postgresql/9.5/main/postgresql.conf
                    echo "Configuring checkpoint settings"
                    sed -i "s/#checkpoint_timeout = 5min/checkpoint_timeout = 20min/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#max_wal_size = 1GB/max_wal_size = 2GB/" /etc/postgresql/9.5/main/postgresql.conf
                    sed -i "s/#checkpoint_completion_target = 0.5/checkpoint_completion_target = 0.7/" /etc/postgresql/9.5/main/postgresql.conf
                fi
                echo "Done with changing postgresql settings, we need to restart postgres for them to take effect"
            fi

            # set network
            if [ "${CLOUD}" = "google" ]; then
                SUBNET=`gcloud compute networks subnets list | grep europe-west1 | awk '{ print $4 }'`
            else
                SUBNET="10.0.1.0/24"
            fi
            # set permissions
            if [ -e "/etc/postgresql/9.5/main/pg_hba.conf" ]; then
                #echo "host    all             all             $SUBNET           trust" >> /etc/postgresql/9.5/main/pg_hba.conf
                #sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/9.5/main/postgresql.conf
                sed -i "s/host    all             all             127.0.0.1\/32            md5/#host    all             all             127.0.0.1\/32            md5/" /etc/postgresql/9.5/main/pg_hba.conf
                echo "host    all             all             127.0.0.1/32           trust" >> /etc/postgresql/9.5/main/pg_hba.conf
            fi

            echo "Welcome to Resource ${RESOURCE_INDEX} - ${HOSTNAME} (${IP})"

            echo "(re)Start postgres db ..."
            # service postgresql restart # Gives no output, so take old school one
            /etc/init.d/postgresql restart

            # install my .psqlrc file
            cp /tmp/rcfiles/psqlrc /var/lib/postgresql/.psqlrc

            # create 2 tablespaces for index and for data
            mkdir /datadisk1/pg_db /datadisk2/pg_in /datadisk1/scratch

            # make a temp area for deploy user usage
            chown ${DEPLOY_USER}:${DEPLOY_USER} /datadisk1/scratch

            # change the ownership of the new files
            chown postgres:postgres /datadisk1/pg_db /datadisk2/pg_in /var/lib/postgresql/.psqlrc

            cat > /tmp/install.tablespaces.sql << EOF
CREATE TABLESPACE dbspace LOCATION '/datadisk1/pg_db';
CREATE TABLESPACE indexspace LOCATION '/datadisk2/pg_in';
GRANT ALL PRIVILEGES ON TABLESPACE dbspace TO "${USER}" WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON TABLESPACE indexspace TO "${USER}" WITH GRANT OPTION;
EOF

            # set default TS
            cat > /tmp/alter.ts.sql << EOF
ALTER DATABASE ${DB} SET TABLESPACE dbspace;
ALTER TABLE ALL IN TABLESPACE pg_default OWNED BY "${USER}" SET TABLESPACE dbspace;
ALTER INDEX ALL IN TABLESPACE pg_default OWNED BY "${USER}" SET TABLESPACE indexspace;
EOF

            echo "${GREEN}Preparing Database ... $DB / $USER ${RESET}"
            # su postgres -c "dropdb $DB --if-exists"

            if ! su - postgres -c "psql -d $DB -c '\q' 2>/dev/null"; then
                su - postgres -c "createuser $USER"
                su - postgres -c "createdb --encoding='utf-8' --owner=$USER '$DB'"
            fi

            # create additional DB for alternative datatest
            if [ "${RES_ARRAY[1]}" = "db" ]; then
                echo "${GREEN}Creating 2nd GIS db${RESET}"
                if ! su - postgres -c "psql -d $DATA_DB -c '\q' 2>/dev/null"; then
                    su - postgres -c "createdb --encoding='utf-8' --owner=$USER '$DATA_DB'"
                fi
            fi
            echo "${GREEN}GRANT privileges on tablespaces to $USER ${RESET}"
            su - postgres -c "cat /tmp/install.tablespaces.sql | psql"

            [ -x /etc/init.d/renderd ] && /etc/init.d/renderd stop
            su - postgres -c "cat /tmp/alter.ts.sql | psql"
            [ -x /etc/init.d/renderd ] && /etc/init.d/renderd start

            echo "${GREEN}Changing user password ...${RESET}"
            cat > /tmp/install.postcreate.sql << EOF
ALTER USER "$USER" WITH PASSWORD '${PASSWORD}';
EOF

            su - postgres -c "cat /tmp/install.postcreate.sql | psql -d $DB"

            echo "Installing POSTGIS extentions..."

            cat > /tmp/install.postgis.sql << EOF
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;
CREATE EXTENSION hstore;
EOF

            if su - postgres -c "psql -d $DB -c '\q' 2>/dev/null"; then
                su - postgres -c "cat /tmp/install.postgis.sql | psql -d $DB"
            fi

            if su - postgres -c "psql -d $DATA_DB -c '\q' 2>/dev/null"; then
                su - postgres -c "cat /tmp/install.postgis.sql | psql -d $DATA_DB"
            fi

            # deliver the database (no tables)
            #su - postgres -c "cat /tmp/database.sql | psql"
        fi
    fi
}

function update_noninteractive {
    # Update noninteractive
    DEBIAN_FRONTEND=noninteractive apt-get update --fix-missing -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0
}

function configure_credentials {
    # SSH KEYS Perform this on all nodes that need bitbucket access through deployment keys
    if [ "${RES_ARRAY[1]}" = "db" ]; then
        echo "${GREEN}Registering worker DB credentials${RESET}"
        create_db_ini_file

        echo "Create .pgpass file"
        create_pgpass

        echo "${GREEN}Installing SSH deployment keys${RESET}"

        if [ ! -d "/root/.ssh" ]; then
            mkdir /root/.ssh
        fi

        PERMS=$(stat -c "%a" /root/.ssh)
        if [ ! "${PERMS}" = "0700" ]; then
            chmod 0700 /root/.ssh
        fi

        chmod 600 /root/.ssh/deployment_*rsa
        chmod 644 /root/.ssh/deployment_*pub

        # touch known_hosts
        touch /root/.ssh/known_hosts

        if ! cat /root/ssh/known_hosts | grep -q "bitbucket"; then
            # Add bitbuckets/github keys
            echo "Adding SSH bitbucket host key"
            ssh-keyscan bitbucket.org >> /root/.ssh/known_hosts
        fi

        if ! cat /root/ssh/known_hosts | grep -q "github"; then
            echo "Adding SSH github host key"
            ssh-keyscan github.com >> /root/.ssh/known_hosts
        fi

        ## Fix DEPLOY_USER ssh Permissions
        if [ ! -d "/home/${DEPLOY_USER}/.ssh" ]; then
            echo "Creating user SSH dir if it does not exists"
            mkdir /home/${DEPLOY_USER}/.ssh
            chmod 700 /home/${DEPLOY_USER}/.ssh
            chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
        fi

        ## concat the deployment pub keys into authorize
        if [ -d "/root/.ssh" ]; then
            # for root
            if [ ! -e "/root/.ssh/authorized_keys" ]; then
                [ -r /tmp/configs/authorized.default ] && cat /tmp/configs/authorized.default /root/.ssh/deployment_*.pub >> /root/.ssh/authorized_keys
                [ -r /root/.ssh/authorized_keys ] && chmod 644 /root/.ssh/authorized_keys
            fi
            # for user
            # deploy keys
            if [ -r "/tmp/configs/authorized.default" ]; then
                if [ ! -e "/home/${DEPLOY_USER}/.ssh/authorized_keys" ]; then
                    cat /tmp/configs/authorized.default /root/.ssh/deployment_*.pub >> /home/${DEPLOY_USER}/.ssh/authorized_keys
                    # individual user keys (start with user_* )
                    cat /tmp/configs/authorized.default /root/.ssh/user_*.pub >> /home/${DEPLOY_USER}/.ssh/authorized_keys
                    chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/authorized_keys
                    chmod 644 /home/${DEPLOY_USER}/.ssh/authorized_keys
                fi
            fi
        fi

        ## Copy all deployment keys priv/public to the deploy user ssh dir
        if [ -d "/root/.ssh" ]; then
            if [ -r "/root/.ssh/config" ]; then
                if [ ! -e "/home/${DEPLOY_USER}/.ssh/config" ]; then
                    cp /root/.ssh/config /home/${DEPLOY_USER}/.ssh/
                    cp /root/.ssh/deployment_* /home/${DEPLOY_USER}/.ssh/
                    chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/deployment_*
                fi
            fi
        fi
        ## This user will be able to use rsync etc to connect internally.
        # Add bitbuckets/github keys to deploy user too
        if ! cat /home/${DEPLOY_USER}/.ssh/known_hosts | grep -q "bitbucket"; then
            sudo su - $DEPLOY_USER -c "ssh-keyscan bitbucket.org >> /home/${DEPLOY_USER}/.ssh/known_hosts"
        fi
        if ! cat /home/${DEPLOY_USER}/.ssh/known_hosts | grep -q "github"; then
            sudo su - $DEPLOY_USER -c "ssh-keyscan github.com >> /home/${DEPLOY_USER}/.ssh/known_hosts"
        fi
    fi
}

function configure_crontabs {
    if [ "${RES_ARRAY[1]}" = "db" ]; then
        if [ ! -e "/var/spool/cron/crontabs/${DEPLOY_USER}" ]; then
            echo "${GREEN}Setting up ${DEPLOY_USER} cron${RESET}"
            # Install cron tabs
            # specific server type crontabs
            # deploy user crontabs (currently for db and core)
            GROUP=${RES_ARRAY[1]} # = "www"
            if [ -r /tmp/crons/cron_${GROUP}_${DEPLOY_USER}.txt ]; then
                cat /tmp/crons/cron_${GROUP}_${DEPLOY_USER}.txt >> /var/spool/cron/crontabs/${DEPLOY_USER}
                chown ${DEPLOY_USER}:crontab /var/spool/cron/crontabs/${DEPLOY_USER}
                chmod 0600 /var/spool/cron/crontabs/${DEPLOY_USER}
            fi
        fi

        if [ ! -e "/var/spool/cron/crontabs/root" ]; then
            echo "${GREEN}Setting up root cron${RESET}"
            # One cron for root on all nodes
            cat /tmp/crons/cron_all_root.txt >> /var/spool/cron/crontabs/root
            chown root:crontab /var/spool/cron/crontabs/root
            chmod 0600 /var/spool/cron/crontabs/root
        fi
    fi
    # Restart service(s)
    /etc/init.d/cron restart
}

function install_json_bash {
    echo "${GREEN}Install json bash${RESET}"
    if [ ! -d "/usr/local/src/json_bash" ]; then
        # For all machines, install json parser
        cd /usr/local/src && git clone https://github.com/gplv2/JSON.sh json_bash && cd /usr/local/src/json_bash && cp JSON.sh /usr/local/bin/json_parse && chmod +x /usr/local/bin/json_parse
    fi
}

function configure_hostnames {
    echo "${GREEN}Registering internal host names${RESET}"
    if [ -e /usr/local/bin/json_parse ] && [ -x /usr/local/bin/json_parse ] && [ "${CLOUD}" = "google" ]; then
        MYNAME=$(/usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $1 }')
        if ! cat /etc/hosts | grep -q $MYNAME ; then
            # Complete the hosts file with our internal ip/hostnames
            /usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $2 " " $1 }' >> /etc/hosts
        fi
        # DSH machine list
        if ! cat /etc/dsh/machines.list | grep -q $MYNAME ; then
            echo "building DSH machine list"
            /usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $1 }' > /etc/dsh/machines.list
        fi
        # groups
    fi
}

function configure_ssh_config {
    echo "${GREEN}Configure SSH${RESET}"
    if [ "${CLOUD}" = "google" ]; then
        echo "${GREEN}Registering all servers with deploy user ssh id/keys${RESET}"
        HOSTS=`/usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $1 }'`

        if ! cat /home/${DEPLOY_USER}/.ssh/config| grep -q 'start autoadded by'; then
            echo "# start autoadded by provisioning" >> /home/${DEPLOY_USER}/.ssh/config
        fi

        for host in ${HOSTS}
        do
            if ! cat /home/${DEPLOY_USER}/.ssh/config| grep -q $host ; then
            cat << EOF >> /home/${DEPLOY_USER}/.ssh/config
Host $host
  HostName $host
  PreferredAuthentications publickey
  IdentityFile ~/.ssh/deployment_grb_rsa
  StrictHostKeyChecking=no
EOF
            fi
        done
        if ! cat /home/${DEPLOY_USER}/.ssh/config| grep -q 'end autoadded'; then
            echo "# end autoadded" >> /home/${DEPLOY_USER}/.ssh/config
            chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/config
        fi
    fi

    if [ "${RES_ARRAY[1]}" = "db" ]; then
        echo "Restart sshd  ..."
        /etc/init.d/ssh restart
    fi
}

function install_gunicorn {
    echo "${GREEN}Install unicor${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 gunicorn python-pip supervisor

    # install python packages
    su - ${DEPLOY_USER} -c "pip install -U TileStache Pillow modestmaps simplejson werkzeug uuid mbutil"

    #supervisorctl start gunicorn_tilestache # does not work
}


function install_node-tileserver {
    echo "${GREEN}Install node-tileserver${RESET}"
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 php-geoip libgeoip-dev geoip-database geoip-bin php-gettext python-ply python-imaging python-cairo python-cairosvg librsvg2-2 librsvg2-dev libcairo2-dev libcairomm-1.0-dev libjpeg-turbo8-dev libpangomm-1.4-dev libgif-dev
    # $ apt-get install nodejs-legacy # see https://stackoverflow.com/questions/21168141/can-not-install-packages-using-node-package-manager-in-ubuntu for the reason

    # install python packages
    #su - ${DEPLOY_USER} -c "pip install -U TileStache Pillow modestmaps simplejson werkzeug uuid mbutil"
    cd /usr/local/src/ && git clone --recursive https://github.com/rurseekatze/node-tileserver.git && cd node-tileserver && npm -g install

    # You need MapCSS converter to compile your MapCSS styles to JavaScript. Go to your styles directory and compile all your MapCSS styles in one run (you have to do this after every change of your stylesheets):
    #cd /usr/local/src/node-tileserver && for stylefile in *.mapcss ; do python mapcss_converter.py --mapcss "$stylefile" --icons-path . ; done    # does not work
}


echo "${GREEN}Start running general actions${RESET}"

# prepare all servers
silence_dpkg
fix_locales
create_deploy_user

# Setup OS and install apps
install_os_packages
install_selected_packages
install_configure_postgres
update_noninteractive

# configure stuff
configure_credentials
configure_crontabs
install_json_bash
configure_hostnames
configure_ssh_config

echo "${GREEN}Done general stuff${RESET}"
# Build all GRB things, setup db, parse source dat and load into DB
if [ "${RES_ARRAY[1]}" = "db" ]; then
    echo "${GREEN}Running setup..${RESET}"
    install_grb_sources
    create_bash_alias
    make_grb_dirs
    prepare_source_data
    install_compile_packages
    install_carto_compiler
    install_tools
    load_osm_data
    process_source_data
    #  process_3d_source_data

    # tileserver add-ons
    install_mapnik
    install_modtile
    preprocess_carto
    install_shapefiles
    config_modtile
    config_renderd
    install_renderd_service
    install_nginx_tilecache
    install_letsencrypt
    install_test_site
    enable_ssl
    create_osm_indexes
    #transform_srid
    echo "${GREEN}Done database section${RESET}"
fi

echo "${GREEN}Provisioning done${RESET}"
