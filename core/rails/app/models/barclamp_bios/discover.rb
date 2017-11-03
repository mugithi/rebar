#!/usr/bin/ruby
# Copyright (c) 2014 Victor Lowther
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# This file contains the logic needed to do BIOS configuration and
# updates for Dell Poweredge R-series gear.
# It assumes that we can talk to the IPMI controller embedded on the system,
# and that the system has WSMAN enabled.

# Implement everything needed to manage the attributes we care about on
# a Dell R series box.

require 'structurematch'
class BarclampBios::Discover < Role

  def do_transition(nr,data)
    runlog = []
    unless Attrib.get("enable-bios-subsystem",nr.node)
        runlog << "BIOS subsystem is not enabled. Skipping this function."
        runlog << "Set enable-bios-subsystem to true and rerun role to start BIOS processing."
        nr.runlog = runlog.join("\n")
        return
    end

    # Start by making a hash of all our attribs for matching purposes
    matched = Attrib.get("bios-config-sets",nr,:wall)
    unless matched
      matchhash = {}
      nr.node.attribs.each do |a|
        matchhash[a.name] = a.get(nr.node)
      end
      # Get our matchers, score them,
      Attrib.get("bios-set-mapping",nr).map do |a|
        runlog << "Testing #{a["match"].inspect}"
        match = true
        a["match"].each do |k,v|
          match = matchhash.has_key?(k) &&
                  v[0] == "/" &&
                  v[-1] == "/" &&
                  Regexp.compile(v[1..-2]).match(matchhash[k])
          break unless match
        end
        if match
          runlog << "Matched #{a["match"].inspect}"
          matched = a
          break
        end
      end
      unless matched
        runlog << "Cannot find a BIOS config set for #{nr.node.name}"
        runlog << "BIOS settings will not be modified"
        nr.runlog = runlog.join("\n")
        return
      end

      # OK, we need to set our config set and bind the appropriate
      # bios configuration role.
      Attrib.set_without_save('bios-config-sets',nr,matched["configs"],:wall)
      bc_role = Role.find_by!(name: matched["role"])
      chc_role = Role.find_by!(name: 'rebar-hardware-configured')
      unless nr.node.node_roles.find_by(role_id: bc_role.id)
        runlog << "Adding #{bc_role.name} to #{nr.node.name}"
        bc_role.add_to_node(nr.node)
        chc_role.add_to_node(nr.node)
        nr.runlog = runlog.join("\n")
      end
    else
      runlog << "Already matched #{matched} a BIOS config set for #{nr.node.name}"
      nr.runlog = runlog.join("\n")
    end
  end
end
