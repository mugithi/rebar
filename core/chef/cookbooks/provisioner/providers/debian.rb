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

action :add do
  os = "#{new_resource.distro}-#{new_resource.version}"
  proxy = node["rebar"]["proxy"]["servers"].first["url"]
  proxy_addr = node["rebar"]["proxy"]["servers"].first["address"]
  repos = Rebar::fetch_repos_for(node,os)
  params = node["rebar"]["provisioner"]["server"]["supported_oses"][os]
  online = node["rebar"]["provisioner"]["server"]["online"]
  tftproot = node["rebar"]["provisioner"]["server"]["root"]
  provisioner_web = node["rebar"]["provisioner"]["server"]["webservers"].first["url"]
  api_server=node['rebar']['api']['servers'].first["url"]
  ntp_server = "#{node["rebar"]["ntp"]["servers"].first}"
  use_local_security = node["rebar"]["provisioner"]["server"]["use_local_security"]
  os_codename = params["codename"]
  keys = node["rebar"]["access_keys"].values.sort.join($/)
  machine_key = node["rebar"]["machine_key"]
  mnode_name = new_resource.name
  mnode_rootdev = new_resource.rootdev
  node_dir = "#{tftproot}/nodes/#{mnode_name}"
  web_path = "#{provisioner_web}/nodes/#{mnode_name}"
  append = "url=#{web_path}/seed netcfg/get_hostname=#{mnode_name} #{params["append"] || ""} rebar.fqdn=#{mnode_name} rebar.install.key=#{machine_key}"
  os_install_site = "#{provisioner_web}/#{os}/install"
  v4addr = new_resource.address
  kernel = "#{os}/install/#{params["kernel"]}"
  initrd = "#{os}/install/#{params["initrd"]}"
  initrd = "" unless params["initrd"] && !params["initrd"].empty?

  directory node_dir do
    action :create
    recursive true
  end

  template "#{node_dir}/seed" do
    mode 0644
    owner "root"
    group "root"
    source "net_seed.erb"
    variables(:install_name => os,
              :name => mnode_name,
              :cc_use_local_security => use_local_security,
              :os_install_site => os_install_site,
              :online => online,
              :provisioner_web => provisioner_web,
              :web_path => web_path,
              :proxy => proxy,
              :proxy_addr => proxy_addr,
              :rootdev => mnode_rootdev)
  end

  template "#{node_dir}/post-install.sh" do
    mode 0644
    owner "root"
    group "root"
    source "net-post-install.sh.erb"
    variables(:install_name => os,
              :os_codename => os_codename,
              :repos => repos,
              :api_server => api_server,
              :online => online,
              :keys => keys,
              :provisioner_web => provisioner_web,
              :logging_server => api_server, # XXX: FIX this with logging service.
              :proxy => proxy,
              :proxy_addr => proxy_addr,
              :web_path => web_path)
  end

  template "#{node_dir}/rebar_join.sh" do
    mode 0644
    owner "root"
    group "root"
    source "rebar_join.sh.erb"
    variables(:api_server => api_server, :ntp_server => ntp_server, :name => mnode_name)
  end

  provisioner_bootfile mnode_name do
    bootenv "#{os}-install"
    kernel kernel
    initrd initrd
    address v4addr
    kernel_params append
    action :add
  end
  
end
