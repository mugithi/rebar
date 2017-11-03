#! /usr/bin/env python
# Copyright 2015, RackN
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# pip install requests
import requests, json, argparse
from requests.auth import HTTPDigestAuth
  
'''
Usage: https://github.com/digitalrebar/doc/tree/master/clients/ansible
API:  https://github.com/digitalrebar/doc/tree/master/development/api

example: ansible -i inventory.py all -a "uname -a"
'''
    
def main():

    # change these values to match your DigitalRebar installation
    addr = "https://127.0.0.1"
    user = "rebar"
    password = "rebar1"

    # Argument parsing 
    parser = argparse.ArgumentParser(description="Ansible dynamic inventory via DigitalRebar")
    parser.add_argument("--list", help="Ansible inventory of all of the deployments", 
        action="store_true", dest="list_inventory")
    parser.add_argument("--host",
        help="Ansible inventory of a particular host", action="store",
        dest="ansible_host", type=str)

    cli_args = parser.parse_args()
    list_inventory = cli_args.list_inventory
    ansible_host = cli_args.ansible_host

    if list_inventory:
        URL = addr + "/api/status/inventory?hostvar=none"
    elif ansible_host:
        URL = addr + "/api/status/inventory?hostvar=" + ansible_host
    else:
        URL = addr + "/api/status/inventory"

    Auth = HTTPDigestAuth(user,password)
    Headers = {'content-type': 'application/json'}
    print("URL ", URL, " via ", Auth)
    r = requests.get(URL,auth=Auth,headers=Headers,verify=False)

    if r.status_code == 200: 
        print r.text
    else:
        raise IOError(r.text)

if __name__ == "__main__":
    main()  
