#!/bin/bash -e

# RESOURCE_INDEX= grb-db-0
if [ -z "$RESOURCE_INDEX" ] ; then
    RESOURCE_INDEX=`hostname`
fi

CLOUD=google

if [ "${CLOUD}" = "google" ]; then
   # Gather metadata for the whole project, especially IP addresses
   IP=$(curl -s -H "Metadata-Flavor:Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/ip)
else
   IP=$(ifconfig eth0 | awk '/inet addr/ {gsub("addr:", "", $2); print $2}')
fi

# use python inventory script (ansible stuff)
export GCE_INI_PATH=/usr/local/etc/gce.ini

# get the project we belong to
MY_PROJECT=$(<"/etc/myproject")

IFS='-' read -r -a RES_ARRAY <<< "$RESOURCE_INDEX"

for element in "${RES_ARRAY[@]}"
do
    echo "meta: ${element}"
done

PROJECT_NAME=grbapi
PROJECT_DIRECTORY=/var/www/${PROJECT_NAME}
DB=grb_api
USER=grb-data
DEPLOY_USER=glenn

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

echo "Silencing dpkg fancy stuff"
echo 'Dpkg::Progress-Fancy "0";' > /etc/apt/apt.conf.d/01progressbar

echo "Trying to fix locales"
echo "LC_ALL=en_US.UTF-8" >> /etc/environment

# fix locales
locale-gen "en_US.UTF-8"
locale-gen "nl_BE.UTF-8"
locale-gen "fr_BE.UTF-8"

echo "nl_BE.UTF-8 fr_BE.UTF-8 UTF-8" >> /etc/locale.gen

locale-gen

# Functions
function install_tools {
    echo "Going to install our toolbox.."
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 protobuf-compiler

    echo "Building protozero library"
    # Add the protozero libraries here since it was remove from osmium  see:  https://github.com/osmcode/libosmium/commit/bba631a51b3724327ed1a6a247d372da271b25cb
    cd /usr/local/src/ && git clone --recursive https://github.com/mapbox/protozero.git && cd /usr/local/src/protozero && mkdir build && cd build && cmake .. && make -j 6 && make install

    # we gonna need a few tools , start with GDAL (for ogr)
    echo "Building GDAL"
    cd /usr/local/src/ && wget --quiet http://download.osgeo.org/gdal/2.2.0/gdal-2.2.0.tar.gz && tar -xzvf gdal-2.2.0.tar.gz && cd gdal-2.2.0 && ./configure && make -j 6 && make install && ldconfig

    echo "Building osm2pgsql"
    cd /usr/local/src/ && git clone --recursive git://github.com/openstreetmap/osm2pgsql.git && cd /usr/local/src/osm2pgsql && mkdir build && cd build && cmake .. && make -j 6 && make install
    echo "Building libosmium standalone library and osmium tool"
    cd /usr/local/src/ && git clone --recursive https://github.com/osmcode/libosmium.git && git clone https://github.com/osmcode/osmium-tool.git && cd /usr/local/src/libosmium && mkdir build && cd build && cmake .. && make -j 6 && make install && cd /usr/local/src/osmium-tool && mkdir build && cd build && cmake .. && make -j 6 && make install

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
    # copy modified style sheet (wonder if I still need the rest of the source of cartocss (seems to work like this)
    cp /usr/local/src/openstreetmap-carto/openstreetmap-carto.style /usr/local/src/openstreetmap-carto/openstreetmap-carto-orig.style
    #
    cp /tmp/openstreetmap-carto.style /usr/local/src/openstreetmap-carto/openstreetmap-carto.style
    cp /tmp/openstreetmap-carto-3d.style /usr/local/src/openstreetmap-carto/
}

function install_compile_packages {
    # we need to prepare a partial tilesever setup so we can load belgium in a postGIS database , there might be some duplicate packages with the rest of this script
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 libboost-all-dev git-core tar unzip wget bzip2 build-essential autoconf libtool libgeos-dev libgeos++-dev libpq-dev libproj-dev libprotobuf-c0-dev libxml2-dev protobuf-c-compiler libfreetype6-dev libpng12-dev libtiff5-dev libicu-dev libcairo-dev libcairomm-1.0-dev apache2 apache2-dev libagg-dev liblua5.2-dev ttf-unifont liblua5.1-dev libgeotiff-epsg fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted python-yaml make cmake g++ libboost-dev libboost-system-dev libboost-filesystem-dev libexpat1-dev zlib1g-dev libbz2-dev libpq-dev liblua5.2-dev osmctools libprotozero-dev libutfcpp-dev rapidjson-dev pandoc clang-tidy cppcheck iwyu recode

    # postgis is already present, so skip that step, but nodejs is not
    curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -

    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 nodejs
    # these libraries are needed to compile osm2pgsql from source
}

function install_mapnik {
    echo "Installing mapnik"
    # install mapnik, this needs to be run after installing packages from install_compile_packages function
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 libmapnik-dev mapnik-utils python-mapnik
}

function install_modtile {
    echo "installing modtile"

    #mkdir /usr/local/src/grb
    #chown -R ${DEPLOY_USER}:${DEPLOY_USER} /usr/local/src/grb/mapnik

    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb/mapnik && git clone -b switch2osm git://github.com/SomeoneElseOSM/mod_tile.git && cd /usr/local/src/grb/mod_tile && ./autobuild.sh && ./configure && make -j 6"

    if [ $? -eq 0 ]
        then
        echo "Successfully compiled modtile sources, going to install it"
        cd /usr/local/src/grb/mapnik && make install && make install-mod_tile
        ldconfig
    fi
}

function install_carto_compiler {
    echo "installing carto compiler"
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 npm nodejs-legacy fonts-noto-cjk fonts-noto-hinted fonts-noto-unhinted ttf-unifont
    sudo npm install -g carto
    carto -v
}

# /usr/local/src/openstreetmap-carto/openstreetmap-carto-orig.style
function preprocess_carto {
    su - ${DEPLOY_USER} -c "cd /usr/local/src/openstreetmap-carto && carto project.mml > mapnik.xml"
}

function install_shapefiles {
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb/openstreetmap-carto && scripts/get-shapefiles.py"
}

function load_osm_data {
    # the data should be present in /usr/loca/src/grb workdir
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://download.geofabrik.de/europe/belgium-latest.osm.pbf"
    # make use of the pgsql tablespace setup having the indexes on a second disk, this speeds up import significantly
    #      --tablespace-main-data    tablespace for main tables
    #      --tablespace-main-index   tablespace for main table indexes
    #      --tablespace-slim-data    tablespace for slim mode tables
    #      --tablespace-slim-index   tablespace for slim mode indexes

    # since we use a good fat machine with 4 processeors, lets use 3 for osm2pgsql and keep one for the database
    /usr/local/bin/osm2pgsql --slim --create -l --cache 8000 --number-processes 3 --hstore --style /usr/local/src/openstreetmap-carto/openstreetmap-carto-orig.style --multi-geometry -d ${DATA_DB} -U grb-data /usr/local/src/grb/belgium-latest.osm.pbf -H grb-db-0 --tablespace-main-data dbspace --tablespace-main-index indexspace --tablespace-slim-data dbspace --tablespace-slim-index indexspace
}

function process_source_data {
    # call external script
    chmod +x /tmp/process_source.sh
    su - ${DEPLOY_USER} -c "/tmp/process_source.sh"

    # now move all the indexes to the second disk for speed (the tables will probably be ok but the indexes not (no default ts)
    su - postgres -c "cat /tmp/alter.ts.sql | psql"
}

function process_3d_source_data {
    # call external script
    chmod +x /tmp/process_3D_source.sh
    su - ${DEPLOY_USER} -c "/tmp/process_3D_source.sh"

    # now move all the indexes to the second disk for speed (the tables will probably be ok but the indexes not (no default ts)
    su - postgres -c "cat /tmp/alter.ts.sql | psql"

    #su - postgres -c "cat /tmp/alter.ts.sql | psql -U grb-data grb_api -h grb-db-0"
}


function create_db_ini_file {
   echo "user     = ${USER}" > $DB_CREDENTIALS
   echo "database = ${DATA_DB}" >> $DB_CREDENTIALS
   echo "host     = grb-db-0" >> $DB_CREDENTIALS
   echo "password = ${PASSWORD}" >> $DB_CREDENTIALS
}

function prepare_source_data {
    # downloading GRB data from private CDN or direct source
    echo "downloading all source data"
    mkdir /usr/local/src/grb
    mkdir /datadisk2/out
    chown -R ${DEPLOY_USER}:${DEPLOY_USER} /usr/local/src/grb
    chown -R ${DEPLOY_USER}:${DEPLOY_USER} /datadisk2/out

    echo "downloading GRB extracts (mirror)"
    # wget seems to exhibit a bug in combination with running from terraform, quiet fixes that
    # this is using my own mirror of the files as the download process with AGIV doesn't really work with automated downloads
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_10000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_20001B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_30000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_40000B500.zip"
    su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && wget --quiet http://debian.byte-consult.be/grb/GRBgis_20171105_70000B500.zip"

    echo "downloading GRB 3D extracts (mirror)"
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
        echo "Done mounting zip sources"
    else
        echo "extracting GRB data..."
        # unpacking all provinces data
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_10000B500.zip -d GRBgis_10000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_20001B500.zip -d GRBgis_20001"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_30000B500.zip -d GRBgis_30000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_40000B500.zip -d GRBgis_40000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip GRBgis_20171105_70000B500.zip -d GRBgis_70000"
        # GRBgis_10000 GRBgis_20001 GRBgis_30000 GRBgis_40000 GRBgis_70000

        echo "extracting 3D data..."
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_04000B500.zip -d 3D_GRB_04000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_30000B500.zip -d 3D_GRB_30000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_20001B500.zip -d 3D_GRB_20001"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_40000B500.zip -d 3D_GRB_40000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_70000B500.zip -d 3D_GRB_70000"
        su - ${DEPLOY_USER} -c "cd /usr/local/src/grb && unzip 3D_GRB_10000B500.zip -d 3D_GRB_10000"
        # 3D_GRB_04000 3D_GRB_30000 3D_GRB_20001 3D_GRB_40000 3D_GRB_70000 3D_GRB_10000
        echo "Done extracting and preparing sources"
    fi
}

# Create an aliases file so we can use short commands to navigate a project
function create_bash_alias {
    echo "Setting up bash aliases : psqlc home"
    # the db alias : psql -h grb-db-0 -d grb-temp -U grb-data
cat > /root/.bash_aliases << EOF
alias psqlc='psql -h grb-db-0 -d ${DATA_DB} -U ${USER}'
alias home='cd ${PROJECT_DIRECTORY}'
EOF
}

function install_grb_sources {
    echo "Install GRB source code ..."
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

# Generating locales...
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales

# Fix package problems
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

echo "Provisioning GCE(vm): ${RES_ARRAY[1]} / ${RES_ARRAY[2]}"
# Adding a deploy user

PASS=YgjwiWbc2UWG.
SPASS=`openssl passwd -1 $PASS`
/usr/sbin/useradd -p $SPASS --create-home -s /bin/bash -G www-data $DEPLOY_USER

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

# for all servers
echo "Install specific packages ..."

if [ "${RES_ARRAY[1]}" = "www" ]; then
    if [ "$DISTRIB_RELEASE" = "16.04" ]; then
        echo "Install $DISTRIB_RELEASE packages ..."
        DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties curl cmake openssl libssl-dev phpunit php7.0 php-dev php-pear pkg-config pkgconf pkg-php-tools g++ make memcached libmemcached-dev python3-software-properties php-memcached php-memcache php-cli php-mbstring cmake php-pgsql node-uglify

        touch /home/${DEPLOY_USER}/.hushlogin
        chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.hushlogin
    fi

    if [ "$DISTRIB_RELEASE" = "16.04" ]; then
        echo "Updating global Composer ..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
fi


if [ "${RES_ARRAY[1]}" = "db" ]; then
    if [ "$DISTRIB_RELEASE" = "16.04" ]; then
        echo "Install $DISTRIB_RELEASE packages ..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties curl cmake openssl libssl-dev phpunit php7.0 php-dev php-pear pkg-config pkgconf pkg-php-tools g++ make memcached libmemcached-dev python3-software-properties php-memcached php-memcache php-cli php-mbstring cmake php-pgsql osmosis

        touch /home/${DEPLOY_USER}/.hushlogin
        chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.hushlogin
    fi

    if [ "$DISTRIB_RELEASE" = "16.04" ]; then
        echo "Updating global Composer ..."
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
fi

# DB server
if [ "${RES_ARRAY[1]}" = "db" ]; then
    echo "Setting up shared mem"
    chmod +x /usr/local/bin/shmsetup.sh
    /usr/local/bin/shmsetup.sh >> /etc/sysctl.conf

    echo "Installing postgres DB server ..."
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
            postgres_shared=`expr $shmmax / 1024 / 1024 / 1000`
            echo "Postgres shared buffer size in GB: ${postgres_shared}"
            echo "Configuring memory settings"
            sed -i "s/shared_buffers = 128MB/shared_buffers = ${postgres_shared}GB/" /etc/postgresql/9.5/main/postgresql.conf
            sed -i "s/#work_mem = 4MB/work_mem = 256MB/" /etc/postgresql/9.5/main/postgresql.conf
            sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = 1024MB/" /etc/postgresql/9.5/main/postgresql.conf
            sed -i "s/#full_page_writes = on/full_page_writes = on/" /etc/postgresql/9.5/main/postgresql.conf
            sed -i "s/#fsync = on/fsync = on/" /etc/postgresql/9.5/main/postgresql.conf
            sed -i "s/#temp_buffers = 8MB/temp_buffers = 16MB/" /etc/postgresql/9.5/main/postgresql.conf
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
        echo "host    all             all             $SUBNET           trust" >> /etc/postgresql/9.5/main/pg_hba.conf
    fi

    echo "Welcome to Resource ${RESOURCE_INDEX} - ${HOSTNAME} (${IP})"

    echo "(re)Start postgres db ..."
    # service postgresql restart # Gives no output, so take old school one
    /etc/init.d/postgresql restart

    # install my .psqlrc file
    cp /tmp/rcfiles/psqlrc /var/lib/postgresql/.psqlrc

    # create 2 tablespaces for index and for data
    mkdir /datadisk1/pg_db /datadisk2/pg_in

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

    echo "Preparing Database ... $DB / $USER "
    # su postgres -c "dropdb $DB --if-exists"

    if ! su - postgres -c "psql -d $DB -c '\q' 2>/dev/null"; then
        su - postgres -c "createuser $USER"
        su - postgres -c "createdb --encoding='utf-8' --owner=$USER '$DB'"
    fi

    # create additional DB for alternative datatest
    if [ "${RES_ARRAY[1]}" = "db" ]; then
        echo "Creating 2nd GIS db"
       if ! su - postgres -c "psql -d $DATA_DB -c '\q' 2>/dev/null"; then
          su - postgres -c "createdb --encoding='utf-8' --owner=$USER '$DATA_DB'"
       fi
    fi
    echo "GRANT privileges on tablespaces to $USER"
    su - postgres -c "cat /tmp/install.tablespaces.sql | psql"
    su - postgres -c "cat /tmp/alter.ts.sql | psql"

    echo "Changing user password ..."
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

# Update noninteractive
DEBIAN_FRONTEND=noninteractive apt-get update --fix-missing -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Use-Pty=0

# SSH KEYS Perform this on all nodes that need bitbucket access through deployment keys (currently www, core, cruncher
if [ "${RES_ARRAY[1]}" = "db" ]; then
    echo "Registering worker DB credentials"
    create_db_ini_file
    echo "Installing SSH deployment keys"

    if [ ! -d "/root/.ssh" ]; then
        mkdir /root/.ssh
    fi

    PERMS=$(stat -c "%a" /root/.ssh)
    if [ ! "${PERMS}" = "0700" ]; then
        chmod 0700 /root/.ssh
    fi

    chmod 600 /root/.ssh/deployment_*rsa
    chmod 644 /root/.ssh/deployment_*pub

    #chmod 644 /root/.ssh/config

    echo "Adding SSH bitbucket host key"
    # Create known_hosts
    touch /root/.ssh/known_hosts

    # Add bitbuckets/github keys
    ssh-keyscan bitbucket.org >> /root/.ssh/known_hosts
    ssh-keyscan github.com >> /root/.ssh/known_hosts
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
        [ -r /tmp/configs/authorized.default ] && cat /tmp/configs/authorized.default /root/.ssh/deployment_*.pub >> /root/.ssh/authorized_keys
        [ -r /root/.ssh/authorized_keys ] && chmod 644 /root/.ssh/authorized_keys

	# for user
        # deploy keys
        if [ -r "/tmp/configs/authorized.default" ]; then
            cat /tmp/configs/authorized.default /root/.ssh/deployment_*.pub >> /home/${DEPLOY_USER}/.ssh/authorized_keys
            # individual user keys (start with user_* )
            cat /tmp/configs/authorized.default /root/.ssh/user_*.pub >> /home/${DEPLOY_USER}/.ssh/authorized_keys
            chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/authorized_keys
            chmod 644 /home/${DEPLOY_USER}/.ssh/authorized_keys
        fi
    fi

    ## Copy all deployment keys priv/public to the deploy user ssh dir
    if [ -d "/root/.ssh" ]; then
        if [ -r "/root/.ssh/config" ]; then
    	    cp /root/.ssh/config /home/${DEPLOY_USER}/.ssh/
            cp /root/.ssh/deployment_* /home/${DEPLOY_USER}/.ssh/
            chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/deployment_*
        fi
    fi
    ## This user will be able to use rsync etc to connect internally.
    # Add bitbuckets/github keys to deploy user too
    sudo su - $DEPLOY_USER -c "ssh-keyscan bitbucket.org >> /home/${DEPLOY_USER}/.ssh/known_hosts"
    sudo su - $DEPLOY_USER -c "ssh-keyscan github.com >> /home/${DEPLOY_USER}/.ssh/known_hosts"

    # Install cron tabs

    # specific server type crontabs
    # deploy user crontabs (currently for db and core)
    GROUP=${RES_ARRAY[1]} # = "www"
    if [ -r /tmp/crons/cron_${GROUP}_${DEPLOY_USER}.txt ]; then
        cat /tmp/crons/cron_${GROUP}_${DEPLOY_USER}.txt >> /var/spool/cron/crontabs/${DEPLOY_USER}
        chown ${DEPLOY_USER}:crontab /var/spool/cron/crontabs/${DEPLOY_USER}
        chmod 0600 /var/spool/cron/crontabs/${DEPLOY_USER}
    fi

    # One cron for root on all nodes
    cat /tmp/crons/cron_all_root.txt >> /var/spool/cron/crontabs/root
    chown root:crontab /var/spool/cron/crontabs/root
    chmod 0600 /var/spool/cron/crontabs/root
fi

# For all machines, install json parser
cd /usr/local/src && git clone https://github.com/gplv2/JSON.sh json_bash && cd /usr/local/src/json_bash && cp JSON.sh /usr/local/bin/json_parse && chmod +x /usr/local/bin/json_parse

echo "Registering internal host names"
if [ -e /usr/local/bin/json_parse ] && [ -x /usr/local/bin/json_parse ] && [ "${CLOUD}" = "google" ]; then
    # Complete the hosts file with our internal ip/hostnames
    /usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $2 " " $1 }' >> /etc/hosts
    # DSH machine list
    echo "building DSH machine list"
    /usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $1 }' > /etc/dsh/machines.list
    # groups
fi

if [ "${CLOUD}" = "google" ]; then
   echo "Registering all servers with deploy user ssh id/keys"
   HOSTS=`/usr/local/bin/json_parse < /etc/projectdata.json | grep '"gce_private_ip"\]' | sed -e 's/\["_meta","hostvars","//g' | sed -e 's/","gce_private_ip"]//g' | sed -e 's/"//g'| awk '{ print $1 }'`

   echo "# start autoadded by provisioning" >> /home/${DEPLOY_USER}/.ssh/config

   for host in ${HOSTS}
   do
cat << EOF >> /home/${DEPLOY_USER}/.ssh/config
Host $host
  HostName $host
  PreferredAuthentications publickey
  IdentityFile ~/.ssh/deployment_grb_rsa
  StrictHostKeyChecking=no
EOF
   done
   echo "# end autoadded" >> /home/${DEPLOY_USER}/.ssh/config
   chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/config
fi

# Restart service(s)
/etc/init.d/cron restart

if [ "${RES_ARRAY[1]}" = "db" ]; then
    echo "Restart sshd  ..."
    /etc/init.d/ssh restart
fi

# Build all GRB things, setup db, parse source dat and load into DB
if [ "${RES_ARRAY[1]}" = "db" ]; then
   install_grb_sources
   create_bash_alias
   prepare_source_data
   install_compile_packages
   install_tools
#  process_source_data
   process_3d_source_data
   load_osm_data
# tileserver add-on
   install_mapnik
   install_modtile
   install_carto_compiler
   preprocess_carto
   install_shapefiles
fi

echo "Provisioning done"
