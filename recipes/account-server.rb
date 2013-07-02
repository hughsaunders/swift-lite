#
# Cookbook Name:: swift
# Recipe:: account-server
#
# Copyright 2012, Rackspace US, Inc.
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

include_recipe "swift-lite::common"
include_recipe "swift-lite::storage-common"

platform_options = node["swift"]["platform"]

platform_options["account_packages"].each.each do |pkg|
  package pkg do
    action node["swift"]["package_action"].to_sym
    options platform_options["override_options"] # retain configs
  end
end

# epel/f-17 missing init scripts for the non-major services.
# https://bugzilla.redhat.com/show_bug.cgi?id=807170
%w{auditor reaper replicator}.each do |svc|
  template "/etc/systemd/system/openstack-swift-account-#{svc}.service" do
    owner "root"
    group "root"
    mode "0644"
    source "simple-systemd-config.erb"
    variables({ :description => "OpenStack Object Storage (swift) - " +
                "Account #{svc.capitalize}",
                :user => "swift",
                :exec => "/usr/bin/swift-account-#{svc} " +
                "/etc/swift/account-server.conf"
              })
    only_if { platform?(%w{fedora}) }
  end
end

# TODO(breu): track against upstream epel packages to determine if this
# is still necessary
# https://bugzilla.redhat.com/show_bug.cgi?id=807170
%w{auditor reaper replicator}.each do |svc|
  template "/etc/init.d/openstack-swift-account-#{svc}" do
    owner "root"
    group "root"
    mode "0755"
    source "simple-redhat-init-config.erb"
    variables({ :description => "OpenStack Object Storage (swift) - " +
                "Account #{svc.capitalize}",
                :user => "swift",
                :exec => "account-#{svc}"
              })
    only_if { platform?(%w{redhat centos}) }
  end
end

%w{swift-account swift-account-auditor swift-account-reaper swift-account-replicator}.each do |svc|
  service_name = platform_options["service_prefix"] + svc + platform_options["service_suffix"]
  service svc do
    service_name service_name
    provider platform_options["service_provider"]
    supports :status => true, :restart => true
    action [:enable, :start]
    only_if "[ -e /etc/swift/account-server.conf ] && [ -e /etc/swift/account.ring.gz ]"
  end
end

account_endpoint = get_bind_endpoint("swift","account-server")

template "/etc/swift/account-server.conf" do
  source "account-server.conf.erb"
  owner "swift"
  group "swift"
  mode "0600"
  variables("bind_ip" => account_endpoint["host"],
            "bind_port" => account_endpoint["port"])

  notifies :restart, "service[swift-account]", :immediately
  notifies :restart, "service[swift-account-auditor]", :immediately
  notifies :restart, "service[swift-account-reaper]", :immediately
  notifies :restart, "service[swift-account-replicator]", :immediately
end

dsh_group "swift-account-servers" do
  user node["swift"]["dsh"]["user"]
  network node["swift"]["dsh"]["network"]
end
