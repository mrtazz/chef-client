#
# Author:: Joshua Timberman (<joshua@chef.io>)
# Author:: Seth Chisamore (<schisamo@chef.io>)
# Author:: Bryan Berry (<bryan.berry@gmail.com>)
# Cookbook::  chef-client
# Recipe:: cron
#
# Copyright:: 2009-2017, Chef Software Inc.
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

require 'digest/md5'

# include helper methods
class ::Chef::Recipe
  include ::Opscode::ChefClient::Helpers
end

# libraries/helpers.rb method to DRY directory creation resources
client_bin = find_chef_client
node.default['chef_client']['bin'] = client_bin
create_chef_directories

dist_dir, conf_dir = value_for_platform_family(
  ['amazon'] => %w( redhat sysconfig ),
  ['debian'] => %w( debian default ),
  ['rhel'] => %w( redhat sysconfig ),
  ['fedora'] => %w( redhat sysconfig ),
  ['suse'] => %w( suse sysconfig )
)

# Stop any running chef-client services
if node['os'] == 'linux'
  template '/etc/init.d/chef-client' do
    source "#{dist_dir}/init.d/chef-client.erb"
    mode '0755'
    variables(client_bin: client_bin)
  end

  template "/etc/#{conf_dir}/chef-client" do
    source "#{dist_dir}/#{conf_dir}/chef-client.erb"
    mode '0644'
  end

  service 'chef-client' do
    supports status: true, restart: true
    provider Chef::Provider::Service::Upstart if node['chef_client']['init_style'] == 'upstart'
    action [:disable, :stop]
  end
end

case node['platform_family']
when 'openindiana', 'opensolaris', 'nexentacore', 'solaris2', 'smartos', 'omnios'
  service 'chef-client' do
    supports status: true, restart: true
    action [:disable, :stop]
    provider Chef::Provider::Service::Solaris
    ignore_failure true
  end

when 'freebsd'
  template '/etc/rc.d/chef-client' do
    owner 'root'
    group 'wheel'
    variables client_bin: client_bin
    mode '0755'
  end

  file '/etc/rc.conf.d/chef' do
    action :delete
  end

  service 'chef-client' do
    supports status: true, restart: true
    action [:stop]
  end
end

# Generate a uniformly distributed unique number to sleep.
if node['chef_client']['splay'].to_i > 0
  seed = node['shard_seed'] || Digest::MD5.hexdigest(node.name).to_s.hex
  sleep_time = seed % node['chef_client']['splay'].to_i
else
  sleep_time = nil
end
log_file   = node['chef_client']['cron']['log_file']
append_log = node['chef_client']['cron']['append_log'] ? '>>' : '>'
daemon_options = " #{node['chef_client']['daemon_options'].join(' ')} " if node['chef_client']['daemon_options'].any?

# If "use_cron_d" is set to true, delete the cron entry that uses the cron
# resource built in to Chef and instead use the cron_d LWRP.
if node['chef_client']['cron']['use_cron_d']
  cron 'chef-client' do
    action :delete
  end

  cron_d 'chef-client' do
    minute  node['chef_client']['cron']['minute']
    hour    node['chef_client']['cron']['hour']
    weekday node['chef_client']['cron']['weekday']
    path    node['chef_client']['cron']['path'] if node['chef_client']['cron']['path']
    mailto  node['chef_client']['cron']['mailto'] if node['chef_client']['cron']['mailto']
    user    'root'
    cmd = ''
    cmd << "/bin/sleep #{sleep_time}; " if sleep_time
    cmd << "#{env_vars} " if env_vars?
    cmd << "/bin/nice -n #{process_priority} " if process_priority
    cmd << "#{client_bin} #{daemon_options}#{append_log} #{log_file} 2>&1"
    command cmd
  end
else
  cron_d 'chef-client' do
    action :delete
  end

  cron 'chef-client' do
    minute  node['chef_client']['cron']['minute']
    hour    node['chef_client']['cron']['hour']
    weekday node['chef_client']['cron']['weekday']
    path    node['chef_client']['cron']['path'] if node['chef_client']['cron']['path']
    mailto  node['chef_client']['cron']['mailto'] if node['chef_client']['cron']['mailto']
    user    'root'
    cmd = ''
    cmd << "/bin/sleep #{sleep_time}; " if sleep_time
    cmd << "#{env_vars} " if env_vars?
    cmd << "/bin/nice -n #{process_priority} " if process_priority
    cmd << "#{client_bin} #{daemon_options}#{append_log} #{log_file} 2>&1"
    command cmd
  end
end
