#!/usr/bin/env bash
DEBIAN_FRONTEND=noninteractive

export $DEBIAN_FRONTEND

printf "Finishing off install"

apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" -f

[ -r /etc/lsb-release ] && . /etc/lsb-release

if [ -z "$DISTRIB_RELEASE" ] && [ -x /usr/bin/lsb_release ]; then
    # Fall back to using the very slow lsb_release utility
    DISTRIB_RELEASE=$(lsb_release -s -r)
    DISTRIB_CODENAME=$(lsb_release -s -c)
fi

printf "Setting up for ubuntu %s - %s\n" "$DISTRIB_RELEASE" "$DISTRIB_CODENAME"

echo "Provisioning virtual machine"

echo "Install packages ..."
# DISTRIB_RELEASE=14.04
if [ "$DISTRIB_RELEASE" = "14.04" ]; then
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" postgresql pkg-config pkgconf g++ make memcached build-essential python-software-properties memcached memcached curl git cmake > /dev/null
fi

# -o Dpkg::Options::=--force-confnew install

if [ "$DISTRIB_RELEASE" = "18.04" ]; then
    echo "Install $DISTRIB_RELEASE packages ..."
    apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" postgresql pkg-config pkgconf g++ make memcached build-essential python-software-properties memcached curl git cmake > /dev/null
    apt-get install -y -o Dpkg::Options::="--force-confnew" php-msgpack > /dev/null
fi

#echo "Updating Composer ..."
#curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
