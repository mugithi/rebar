# Copyright 2013, Dell
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

class BarclampProvisioner::OsInstall < Role

  def on_todo(nr)
    node = nr.node
    return if (["local"].member? node.bootenv) || (nr.run_count > 0)
    node.with_lock('FOR NO KEY UPDATE') do
      disks = Attrib.get('disks',node) || []
      claims = Attrib.get('claimed-disks',node) || {}
      target_disk = Attrib.get('operating-system-disk',node)
      unless target_disk &&
             claims[target_disk] == 'operating system' &&
             disks.any?{|d|d['unique_name'] == target_disk}
        target_disk = nil
        claims.delete_if{|k,v|v == 'operating system'}
        # Grab the first unclaimed nonremovable disk for the OS.
        target_disk = disks.detect{|d|!d["removable"] && !claims[d['unique_name']]}
        # On some systems, all disks are removable.  Try again if we didn't find one.
        target_disk = disks.detect{|d|!claims[d['unique_name']]} unless target_disk
        Attrib.set('operating-system-disk',node,target_disk["unique_name"])
        claims[target_disk["unique_name"]] = "operating system"
        Attrib.set('claimed-disks',node,claims)
      end
      target_os = Attrib.get("provisioner-target_os",nr)
      if target_os.nil? || target_os == ''
        sysdepl = Deployment.system
        default_os = Attrib.get('provisioner-default-os',sysdepl)
        Attrib.set('provisioner-target_os', nr, default_os)
        target_os = default_os
      end
      Rails.logger.info("provisioner-install: Trying to install #{target_os} on #{node.name} (bootenv: #{node.bootenv})")
      node.bootenv = "#{target_os}-install"
      node.save!
    end
  end

end
