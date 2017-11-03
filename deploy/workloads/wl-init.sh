
#
# workloads/wl-init.sh - Provides common functions and help extenders
#

# Prevent recursion
if [[ $WL_INIT_LOADED == true ]] ; then
    return
fi
export WL_INIT_LOADED=true

# Figure out what Linux distro we are running on.
export OS_TYPE= OS_VER= OS_NAME=

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_TYPE=${ID,,}
    OS_VER=${VERSION_ID,,}
elif [[ -f /etc/lsb-release ]]; then
    . /etc/lsb-release
    OS_VER=${DISTRIB_RELEASE,,}
    OS_TYPE=${DISTRIB_ID,,}
elif [[ -f /etc/centos-release || -f /etc/fedora-release || -f /etc/redhat-release ]]; then
    for rel in centos-release fedora-release redhat-release; do
        [[ -f /etc/$rel ]] || continue
        OS_TYPE=${rel%%-*}
        OS_VER="$(egrep -o '[0-9.]+' "/etc/$rel")"
        break
    done
    if [[ ! $OS_TYPE ]]; then
        echo "Cannot determine Linux version we are running on!"
        exit 1
    fi
elif [[ -f /etc/debian_version ]]; then
    OS_TYPE=debian
    OS_VER=$(cat /etc/debian_version)
elif [[ $(uname -s) == Darwin ]] ; then
    OS_TYPE=darwin
    OS_VER=$(sw_vers | grep ProductVersion | awk '{ print $2 }')
fi
OS_NAME="$OS_TYPE-$OS_VER"

case $OS_TYPE in
    centos|redhat|fedora) OS_FAMILY="rhel";;
    debian|ubuntu) OS_FAMILY="debian";;
    *) OS_FAMILY=$OS_TYPE;;
esac

PATH=$PATH:`pwd`

# Load default vars
if [ -f ~/.dr_info ] ; then
    . ~/.dr_info
fi

# Allow for "FORCING" From run-in-*.sh scripts
if [[ $FORCE_PROVIDER ]] ; then
    PROVIDER=$FORCE_PROVIDER
fi
if [[ $FORCE_DEPLOY_ADMIN ]] ; then
    DEPLOY_ADMIN=$FORCE_DEPLOY_ADMIN
fi

die() {
    echo "$@"
    exit 1
}

#
# Functions that help validate or start things.
# 

validate_tools() {
    error=0
    if [ "${BASH_VERSINFO}" -lt 4 ] ; then
        echo "Must have a bash version of 4 or higher"
        error=1
    fi

    if [[ ! -e ~/.ssh/id_rsa ]] ; then
        echo "SSH key missing so we are adding one for you"
        ssh-keygen -t rsa -f ~/.ssh/id_rsa -P ''
    fi

    if ! which sudo &>/dev/null; then
        if [[ $OS_FAMILY == rhel ]] ; then
            yum install -y sudo
        elif [[ $OS_FAMILY == debian ]] ; then
            apt-get install -y sudo
        fi

        if ! which sudo &>/dev/null; then
            echo "Please install sudo!"
            if [[ $(uname -s) == Darwin ]] ; then
                echo "Something like: brew install sudo"
            fi
            error=1
        fi
    fi

    if ! which ansible &>/dev/null; then
        if [[ $OS_FAMILY == rhel ]] ; then
            sudo yum -y install epel-release # Everyone gets epel for free.
            sudo yum install -y ansible python-netaddr
        elif [[ $OS_FAMILY == debian ]] ; then
            sudo apt-get install -y software-properties-common
            sudo apt-add-repository -y ppa:ansible/ansible
            sudo apt-get update -y
            sudo apt-get install -y ansible python-netaddr
        fi

        if ! which ansible &>/dev/null; then
            echo "Please install Ansible!"
            if [[ $OS_FAMILY == darwin ]] ; then
                echo "Something like: brew install ansible or pip install ansible python-netaddr"
            fi
            error=1
        fi
    fi

    if ! which curl &>/dev/null; then
        if [[ $OS_FAMILY == rhel ]] ; then
            sudo yum install -y curl
        elif [[ $OS_FAMILY == debian ]] ; then
            sudo apt-get install -y curl
        fi

        if ! which curl &>/dev/null; then
            echo "Please install curl!"
            if [[ $(uname -s) == Darwin ]] ; then
                echo "Something like: brew install curl"
            fi
            error=1
        fi
    fi

    if ! which jq &>/dev/null; then
        if [[ $OS_FAMILY == rhel ]] ; then
            sudo yum -y install epel-release # Everyone gets epel for free.
            sudo yum install -y jq
        elif [[ $OS_FAMILY == debian ]] ; then
            sudo apt-get install -y jq
        fi

        if ! which jq &>/dev/null; then
            echo "Please install jq!"
            if [[ $(uname -s) == Darwin ]] ; then
                echo "Something like: brew install jq"
            fi
            error=1
        fi
    fi

    if [[ $PROVIDER == aws || $DEPLOY_ADMIN == aws ]] ; then
        if ! which unzip &>/dev/null; then
            if [[ $OS_FAMILY == rhel ]] ; then
                sudo yum install -y unzip
            elif [[ $OS_FAMILY == debian ]] ; then
                sudo apt-get install -y unzip
            fi
        fi

        if ! which aws &>/dev/null; then
            curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
            unzip awscli-bundle.zip
            sudo ./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
            rm -rf awscli-bundle*

            if ! which aws &>/dev/null; then
                echo "Please install aws!"
                error=1
            fi
        fi
    fi

    if [[ $PROVIDER == google || $DEPLOY_ADMIN == google ]] ; then
        if ! which gcloud &>/dev/null; then
            curl https://sdk.cloud.google.com | bash
            exec -l $SHELL
            gcloud init
        fi
    fi

    if [[ $error == 1 ]] ; then
        exit 1
    fi

    REBAR_USER=${REBAR_USER:-rebar}
    REBAR_PASSWORD=${REBAR_PASSWORD:-rebar1}
    export REBAR_KEY=${REBAR_KEY:-$REBAR_USER:$REBAR_PASSWORD}
}

rebar() {
    local rebar_cmd

    rebar_cmd=$(which rebar)
    if [[ $rebar_cmd == "" ]] ; then
        if [[ $(uname -s) == Darwin ]] ; then
            curl -so rebar https://s3-us-west-2.amazonaws.com/rebar-bins/darwin/amd64/rebar
        else
            curl -so rebar https://s3-us-west-2.amazonaws.com/rebar-bins/linux/amd64/rebar
        fi
        chmod +x ./rebar
    fi

    command rebar "$@"
}

usage() {
  echo "Usage $0:"
  echo
  echo "The equals (=) is required for valued options"
  echo
  for i in "${!help_options[@]}"; do
      printf "  %-30s: %s\n"  "$i"  "${help_options[$i]}"
  done | sort 
  echo
  echo "Allowed container services are:"
  for i in "${known_containers[@]}"; do
      printf "  %s\n" $i
  done
  echo "Used by: --con-provisioner or --con-no-provisioner"
  echo
  echo "Allowed workloads are:"
  for i in "${known_workloads[@]}"; do
      printf "  %s\n" $i
  done
  echo "Used by: --wl-digitalrebar-workloads or --wl-no-digitalrebar-workloads"
  echo
}

validate_tools

declare -A help_options

#
# Help commands
#

help_options["--admin-ip=<CIDRIP>"]="Admin IP to use - some providers don't need this"
help_options["--deploy-admin=<environment>"]="Environment to run the admin node in (packet|system|local)"
help_options["--device-id=<String>"]="Device ID of the admin node to use (allows command running for packet)"
help_options["--dr_tag=<TAG>"]="The build tag to use for digitalrebar. default: latest"
help_options["--access=<HOST|FORWARDER>"]="Mode to run the admin node in"
help_options["--rebar-user=<String>"]="Username to access the rebar system"
help_options["--rebar-password=<String>"]="Password to access the rebar system"

help_options["--provider-google-admin-instance-type"]="Google instance type to use for admin nodes"
help_options["--provider-google-instance-type"]="Google instance type to use for nodes"
help_options["--provider-aws-admin-instance-type"]="AWS instance type to use for admin nodes"
help_options["--provider-aws-instance-type"]="AWS instance type to use for nodes"

help_options["--provider-aws-region"]="AWS Region to use for nodes"
help_options["--provider-google-zone"]="Google zone to use for nodes"

help_options["--con-*"]="Container services to enable"
help_options["--con-no-*"]="Container services to disable"
help_options["--wl-*"]="Workload to enable"
help_options["--wl-no-*"]="Worload services to disable"

help_options["--clean-ids"]="Clean the ssh keys authorized_keys file when touching it"
help_options["--id-file=<file>"]="Identity file to use to log into the node to ensure keys are in place"
help_options["--account=<string>"]="User to when initialy logging into systems"
help_options["--init-id-file=<file>"]="File that defines the initial identity"

# Provider config
#
#   --provider=<provider>
#     provider:
#       packet - needs KEY and PROJECT_ID
#       aws - Needs info - needs AWS config
#       system - nothing - needs IP list
#
# Can get from .dr_info or .dr_packet_info instead
#   --provider-packet-key=<key>
#   --provider-packet-project=<project>
#
# Can get from .dr_aws_info instead
#   --provider-aws-??
#   --provider-aws-??
#   --provider-aws-??
#   --provider-aws-??
#
# Can get from .dr_system_info
#   --provider-system-ip-list=<hostnames or ips comma separated>
#

