#!/usr/bin/env bash

if which sudo 2>/dev/null >/dev/null ; then
    SUDO=sudo
fi

SED="sed -i"
if [[ $(uname -s) == Darwin ]] ; then
	SED="sed -i .bak"
fi

SERVICES="network-server logging-service"

function usage {
    echo "Usage: $0 <flags> [options docker-compose flags/commands]"
    echo "  -h or --help - help (this)"
    echo "  --clean - cleans up directory and exits"
    echo "  --access <HOST|FORWARDER> # Defines how the admin containers should be accessed"
    echo "  --dhcp # Adds the dhcp component"
    echo "  --provisioner # Adds the provisioner component"
    echo "  --dns # Adds the dns component"
    echo "  --ntp # Adds the ntp component"
    echo "  --chef # Adds the chef component"
    echo "  --webproxy # Adds the webproxy component"
    echo "  --revproxy # Adds the revproxy component"
    echo "  --logging # Adds the logging (kibana,elasticsearch+) components"
    echo "  --debug # Adds the cadviser components"
    echo "  --node # Adds the node component"
    echo "  --tag <TAG> # Uses that tag for builds and trees. default: latest"
    echo
    echo "  --external_ip <CIDR Address, default: 192.168.124.11/24> "
    echo "  --forwarder_ip <CIDR Address, default: 192.168.124.11/24> "
    echo "       forwarder_ip is ignored if HOST access mode is used."
    echo
    echo " If additional arguments are provided, they are passed to docker-compose"
    echo " Otherwise nothing is run and just files are setup."
}

#
# Sets a value for a variable.
# The variable must exist.
#
function set_var_in_common_env {
  local var=$1
  local value=$2

  $SED -e "s/^${var}=.*/${var}=${value}/" common.env
}

FILES="base.yml trust-me.yml"
REMOVE_FILES=""
ACCESS_MODE="FORWARDER"
PROVISION_IT="NO"
PROXY_IT="NO"

if [[ -f tag ]]; then
    DR_TAG="$(cat tag)"
elif [[ ! $DR_TAG ]]; then
    branch="$(git symbolic-ref -q HEAD)"
    branch="${branch##refs/heads/}"
    branch="${branch:-latest}"
    DR_TAG="${DR_TAG:-${branch}}"
fi
ADD_DNS=false
RUN_NTP="NO"

if [[ ! $DR_TFTPROOT ]]; then
    if [[ $PWD = ${HOME}/* ]]; then
        DR_TFTPROOT="${HOME}/.cache/digitalrebar/tftpboot"
    else
        DR_TFTPROOT="/var/lib/tftpboot"
    fi
fi

mkdir -p "$DR_TFTPROOT"

[[ -e tftpboot ]] || rm -f tftpboot
ln -sf "${DR_TFTPROOT}" tftpboot

while [[ $1 == -* ]] ; do
  arg=$1
  shift

  case $arg in
      --help)
      usage
      exit 0
      ;;
    -h)
      usage
      exit 0
      ;;
    --clean)
        rm -f access.env services.env dc docker-compose.yml config-dir/api/config/networks/*.json tag
        (
            cd "${DR_TFTPROOT}"
            for cfg in *.ipxe *.conf pxelinux.cfg/*; do
                [[ -f $cfg ]] || continue
                case $cfg in
                    default.ipxe|elilo.conf|pxelinux.cfg/default) continue;;
                    *) $SUDO rm -- "$cfg";;
                esac
            done
            for cfg in machines/*; do
                [[ -d $cfg ]] || continue
                $SUDO rm -rf -- "$cfg"
                done
        )
        $SUDO rm -rf data-dir
        if (which selinuxenabled && which chcon) &>/dev/null && selinuxenabled; then
            $SUDO chcon -Rt svirt_sandbox_file_t .
            $SUDO chcon -Rt svirt_sandbox_file_t "${DR_TFTPROOT}"
        fi
      exit 0
      ;;
    --access)
      ACCESS_MODE=$1
      shift
      ;;
    --tag)
      DR_TAG=$1
      shift
      ;;
    --external_ip)
      EXTERNAL_IP=$1
      shift
      ;;
    --forwarder_ip)
      FORWARDER_IP=$1
      shift
      ;;
    --provisioner)
      FILES="$FILES provisioner.yml"
      PROVISION_IT="YES"
      SERVICES+=" provisioner-service"
      ;;
    --ntp)
      FILES="$FILES ntp.yml"
      SERVICES+=" ntp-service"
      RUN_NTP="YES"
      ;;
    --chef)
      FILES="$FILES chef.yml"
      SERVICES+=" chef-service"
      ;;
    --dhcp)
      FILES="$FILES dhcp.yml"
      SERVICES+=" dhcp-mgmt_service dhcp-service"
      ;;
    --dns)
      if [[ $ADD_DNS != true ]] ; then
          FILES="$FILES dns.yml"
      fi
      SERVICES+=" dns-service"
      ADD_DNS=true
      ;;
    --dns-mgmt)
      if [[ $ADD_DNS != true ]] ; then
          FILES="$FILES dns.yml"
      fi
      SERVICES+=" dns-mgmt_service"
      ADD_DNS=true
      ;;
    --webproxy)
      FILES="$FILES webproxy.yml"
      SERVICES+=" proxy-service"
      PROXY_IT="YES"
      ;;
    --revproxy)
      FILES="$FILES revproxy.yml"
      ;;
    --debug)
      FILES="$FILES debug.yml"
      ;;
    --logging)
      FILES="$FILES logging.yml"
      ;;
    --node)
      FILES="$FILES node.yml"
      ;;
  esac

done

if [[ ! $EXTERNAL_IP || $EXTERNAL_IP != */* ]]; then
    echo "$EXTERNAL_IP not set."
    echo "It must be an IPv4 address in CIDR format, e.g:"
    echo "    192.168.124.11/24"
    exit 1
fi

if [ "$ACCESS_MODE" == "FORWARDER" ] ; then
    FORWARDER_IP=${FORWARDER_IP:-${EXTERNAL_IP}}
    ACCESS_MODE_SED_DELETE="HOST"
elif [ "$ACCESS_MODE" == "HOST" ] ; then
    FORWARDER_IP=
    ACCESS_MODE_SED_DELETE="FORWARDER"
else
    echo "ACCESS MODE: $ACCESS_MODE is not HOST or FORWARDER"
    exit 1
fi
(
    cd config-dir/api/config/networks
    cp "$HOME/.cache/digitalrebar/networks/"*.json .
    if [[ $(echo *.json) = '*.sjon' ]]; then
        echo "No networks predefined."
        echo "If you always want to precreate networks in Digital Rebar,"
        echo "please place approporiate definitions in $HOME/.cache/digitalrebar/networks"
        echo
        echo "$PWD/network.json.example is a useful starting point"
    fi
)


if [[ -x ../../go/bin/$DR_TAG/linux/amd64/rebar ]]; then
    mkdir -p data-dir/bin
    cp "../../go/bin/$DR_TAG/linux/amd64/"* data-dir/bin
else
    [[ -d data-dir/bin ]] && rm -rf data-dir/bin
fi

# Process templates and build one big yml file for now.
rm -f docker-compose.yml
for i in $FILES; do
    fname=$i
    if [[ $i != /* ]] ; then
	fname=yaml_templates/$i
    fi
    # Fix Access Mode
    cat "$fname" >> docker-compose.yml
done
$SED -e "/START ACCESS_MODE==${ACCESS_MODE_SED_DELETE}/,/END ACCESS_MODE==${ACCESS_MODE_SED_DELETE}/d" docker-compose.yml

if [[ ! $DEV_MODE = Y ]]; then
    $SED -e "/START DEV_MODE/,/END DEV_MODE/d" docker-compose.yml
fi
$SED -e "/ACCESS_MODE/d" -e '/DEV_MODE/d' docker-compose.yml

if [[ $REMOVE_FILES ]] ; then
	rm -f $REMOVE_FILES
fi

# Find the IP address we should have Consul advertise on
if [[ $(uname -s) == Darwin ]]; then
    CONSUL_ADVERTISE=${DOCKER_HOST%:*}
    CONSUL_ADVERTISE=${CONSUL_ADVERTISE##*/}
elif [[ $(uname -s) == "MINGW64_NT-10.0" ]]; then
    CONSUL_ADVERTISE=${DOCKER_HOST%:*}
    CONSUL_ADVERTISE=${CONSUL_ADVERTISE##*/}
else
    gwdev=$(/sbin/ip -o -4 route show default |head -1 |awk '{print $5}')
    if [[ $gwdev ]]; then
        # First, advertise the address of the device with the default gateway
        CONSUL_ADVERTISE=$(/sbin/ip -o -4 addr show scope global dev "$gwdev" |head -1 |awk '{print $4}')
        CONSUL_ADVERTISE="${CONSUL_ADVERTISE%/*}"
    else
        # Hmmm... we have no access to the Internet.  Pick an address with
        # global scope and hope for the best.
        CONSUL_ADVERTISE=$(/sbin/ip -o -4 addr show scope global |head -1 |awk '{print $4}')
        CONSUL_ADVERTISE="${CONSUL_ADVERTISE%/*}"
    fi
fi
# If we did not get and address to listen on, we are pretty much boned anyways
if [[ ! $CONSUL_ADVERTISE ]]; then
    echo "Could not find an address for Consul to listen on!"
    exit 1
fi
# CONSUL_JOIN is separate from CONSUL_ADVERTISE as futureproofing
CONSUL_JOIN="$CONSUL_ADVERTISE"
# Make access.env for Variables.
cat >access.env <<EOF
USE_OUR_PROXY=$PROXY_IT
EXTERNAL_IP=$EXTERNAL_IP
FORWARDER_IP=$FORWARDER_IP
CONSUL_JOIN=$CONSUL_JOIN
DR_START_TIME=$(date +%s)
RUN_NTP=$RUN_NTP
EOF

# Add proxies from this environment to the containers.
# Need to do similar things
if [[ $http_proxy && $PROXY_IT = NO ]]; then
    cat >>access.env <<EOF
UPSTREAM_HTTP_PROXY=$http_proxy
UPSTREAM_HTTPS_PROXY=$https_proxy
UPSTREAM_NO_PROXY=$no_proxy
EOF
fi

cat >services.env <<EOF
SERVICES=$SERVICES
EOF

cat >config-dir/consul/server-advertise.json <<EOF
{"advertise_addr": "${CONSUL_ADVERTISE}"}
EOF

echo "$DR_TAG" >tag

# With remaining arguments
if [ "$#" -gt 0 ] ; then
    docker-compose $@
fi
