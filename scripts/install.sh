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

echo "nl_BE.UTF-8 UTF-8" >> /etc/locale.gen

locale-gen
# Functions

function create_db_ini_file {
   echo "user     = ${USER}" > $DB_CREDENTIALS
   echo "database = ${DATA_DB}" >> $DB_CREDENTIALS
   echo "host     = grb-db-0" >> $DB_CREDENTIALS
   echo "password = ${PASSWORD}" >> $DB_CREDENTIALS
}

# Create an aliases file so we can use short commands to navigate a project
function create_bash_alias {
    echo "Setting up bash aliases : psqlc home"

    # the db alias : psql -h grb-db-0 -d grb-temp -U grb-data
    PSQL_START="alias psqlc=\''psql -h grb-db-0 -d ${DATA_DB} -U ${USER}'\'"
    echo $PSQL_START >> /root/.bash_aliases
    sudo su - $DEPLOY_USER -c "echo ${PSQL_START} >> ~/.bash_aliases"

    GO_HOME="alias home=\''cd ${PROJECT_DIRECTORY}'\'"
    echo $GO_HOME >> /root/.bash_aliases
    sudo su - $DEPLOY_USER -c "echo ${GO_HOME} >> ~/.bash_aliases"
}

function install_grb_sources {
    echo "Install GRB source code ..."
    su - ${DEPLOY_USER} -c "git clone git@github.com:gplv2/grbtool.git grbtool"
    su - ${DEPLOY_USER} -c "git clone git@github.com:gplv2/grb2osm.git grb2osm"
    su - ${DEPLOY_USER} -c "cd grb2osm && composer install"

    su - ${DEPLOY_USER} -c "git clone git@github.com:gplv2/grb2pgsql.git grb2pgsql"
    su - ${DEPLOY_USER} -c "cd grb2pgsql && git submodule init"
    su - ${DEPLOY_USER} -c "cd grb2pgsql && git submodule update --recursive --remote"
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

DEBIAN_FRONTEND=noninteractive apt-get install -qq -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 zip unzip htop aeson-pretty ccze python3 python3-crypto python3-libcloud jq git rsync dsh monit tree monit postgresql-client-9.5 python-crypto python-libcloud ntpdate

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

if [ "${RES_ARRAY[1]}" = "db" ]; then
    if [ "$DISTRIB_RELEASE" = "16.04" ]; then
        echo "Install $DISTRIB_RELEASE packages ..."
        apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties curl cmake openssl libssl-dev phpunit php7.0 php-dev php-pear pkg-config pkgconf pkg-php-tools g++ make memcached libmemcached-dev python3-software-properties php-memcached php-memcache php-cli php-mbstring cmake php-pgsql

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
        apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 postgresql pkg-config pkgconf g++ make memcached libmemcached-dev build-essential python3-software-properties php-memcached php-memcache libmsgpack-dev curl php-cli php-mbstring cmake php-pgsql pgbouncer postgresql-contrib postgis postgresql-9.5-postgis-2.2
        apt-get install -y -qq -o Dpkg::Options::="--force-confnew" -o Dpkg::Use-Pty=0 php-msgpack
    fi

    # enable listen
    if [ -e "/etc/postgresql/9.5/main/postgresql.conf" ]; then 
        echo "Enable listening on all interfaces"
        sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /etc/postgresql/9.5/main/postgresql.conf
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

    echo "Installing POSTGIS extentions..."

cat > /tmp/install.postgis.sql << EOF
CREATE EXTENSION postgis; CREATE EXTENSION postgis_topology;"
EOF

    su - postgres -c "cat /tmp/install.postgis | psql -d $DB"
    su - postgres -c "cat /tmp/install.postgis | psql -d $DATA_DB"

    echo "Preparing Database ... $DB / $USER "
    # su postgres -c "dropdb $DB --if-exists"

    if ! su - postgres -c "psql -d $DB -c '\q' 2>/dev/null"; then
        su - postgres -c "createuser $USER"
        su - postgres -c "createdb --encoding='utf-8' --owner=$USER '$DB'"
    fi
    
    # create additional DB for raw data storage for preprocessing service (only on db node, not onboarding)
    if [ "${RES_ARRAY[1]}" = "db" ]; then
        echo "Creating worker db "
       if ! su - postgres -c "psql -d $DATA_DB -c '\q' 2>/dev/null"; then
          su - postgres -c "createdb --encoding='utf-8' --owner=$USER '$DATA_DB'"
       fi
    fi

    echo "Changing user password ..."
cat > /tmp/install.postcreate.sql << EOF
ALTER USER "$USER" WITH PASSWORD '${PASSWORD}';
EOF

su - postgres -c "cat /tmp/install.postcreate.sql | psql -d $DB"

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

    #chmod 600 /root/.ssh/deployment_key.rsa
    #chmod 644 /root/.ssh/deployment_key.rsa.pub

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
        cat /tmp/configs/authorized.default /root/.ssh/deployment_*.pub >> /root/.ssh/authorized_keys
        chmod 644 /root/.ssh/authorized_keys
	# for user
        # deploy keys
        cat /tmp/configs/authorized.default /root/.ssh/deployment_*.pub >> /home/${DEPLOY_USER}/.ssh/authorized_keys
        # individual user keys (start with user_* )
        cat /tmp/configs/authorized.default /root/.ssh/user_*.pub >> /home/${DEPLOY_USER}/.ssh/authorized_keys
        chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/authorized_keys
        chmod 644 /home/${DEPLOY_USER}/.ssh/authorized_keys
    fi

    ## Copy all deployment keys priv/public to the deploy user ssh dir 
    if [ -d "/root/.ssh" ]; then
    	cp /root/.ssh/config /home/${DEPLOY_USER}/.ssh/
        cp /root/.ssh/deployment_* /home/${DEPLOY_USER}/.ssh/
        chown ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh/deployment_*
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
  IdentityFile ~/.ssh/deployment_key.rsa
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

# install GRB stuff
if [ "${RES_ARRAY[1]}" = "db" ]; then
   install_grb_sources
   create_bash_alias
fi

echo "Provisioning done"
