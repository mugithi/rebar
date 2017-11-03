#!/usr/bin/env bash
# Copyright 2015, RackN Inc

set -e

if [[ ! -e workload.sh ]]; then
  cd compose
fi

branch="$(git symbolic-ref -q HEAD)"
branch="${branch##refs/heads/}"
branch="${branch:-latest}"

DR_TAG="${DR_TAG:-${branch}}"
if [[ $1 == "--tag" ]] ; then
    shift
    DR_TAG=$1
    shift
fi

while [[ $1 ]]; do
    case "$1" in
        ux)
            ## nop
            shift;;
        digitalrebar-workloads)
            ./workload.sh digitalrebar digitalrebar-workloads
            shift;;
        rackn-workloads)
            ./workload.sh rackn rackn-workloads
            shift;;
        all)
            ./workload.sh digitalrebar digitalrebar-workloads
            ./workload.sh rackn rackn-workloads
            shift;;
        *)
            echo "$1 is not known, use `./workload [organization] [repo]` to install"
            exit -1;;
    esac
done
