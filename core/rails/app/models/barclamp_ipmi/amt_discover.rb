# Copyright 2016 Rackn
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class BarclampIpmi::AmtDiscover < Role

  def on_active(nr)
    unless Attrib.get("enable-amt-subsystem",nr.node)
      Rails.logger.info("AMT not enabled on #{nr.node.name} - system-wide")
      return
    end
    return unless nr.wall['amt']['enable']
    config_role = Role.find_by!(name: 'amt-configure')
    return if NodeRole.find_by(node_id: nr.node_id, role_id: config_role.id)
    config_role.add_to_node(nr.node)
    chc_role = Role.find_by!(name: 'rebar-hardware-configured')
    chc_role.add_to_node(nr.node)
  end

end
