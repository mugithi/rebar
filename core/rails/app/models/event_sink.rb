# Copyright 2016, RackN
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

require 'rest-client'

class EventSink < ActiveRecord::Base

  after_create      :load_uuid

  def load_uuid
    self.reload
  end

  private :load_uuid
  
  validate :check_endpoint_sanity
  has_many :event_selectors

  def self.name_column
    return :endpoint
  end

  def endpoint_method
    endpoint.partition('://')[0]
  end

  def run(event, obj, selector)
    meth, _, rest = endpoint.partition("://")
    case meth
    when 'inproc'
      objklass, _, methpart = rest.partition(':')
      case objklass
      when 'role'
        objname, _ ,methname = methpart.partition('/')
        runobj = Role.find_key(objname)
        meth_sym = methname.to_sym
        runobj.send(meth_sym, obj)
      else
        raise "EventSink.run for inproc:// only handles Role hooks for now"
      end
    when 'http','https'
      data = {}
      data['event'] = event
      data['selector'] = selector
      case
      when obj.is_a?(NodeRole)
        data['deployment'] = obj.node.deployment
        data['node'] = obj.node
        data['role'] = obj.role
        data['node_role'] = obj
      when obj.is_a?(Node)
        data['node'] = obj
        data['deployment'] = obj.deployment
      when obj.is_a?(DeploymentRole)
        data['deployment'] = obj.deployment
        data['role'] = obj.role
        data['deployment_role'] = obj
      when obj.is_a?(Deployment)
        data['deployment'] = obj
      when obj.is_a?(Role)
        data['role'] = obj
      when obj.is_a?(Network)
        data['network'] = obj
      when obj.is_a?(NetworkAllocation)
        data['network'] = obj.network
        data['node'] = obj.node
        data['network_range'] = obj.network_range
        data['network_allocation'] = obj
      when obj.is_a?(NetworkRange)
        data['network'] = obj.network
        data['network_range'] = obj
      when obj.is_a?(NetworkRouter)
        data['network'] = obj.network
        data['network_router'] = obj
      when obj.is_a?(Tenant)
        data['tenant'] = obj
      else
        raise "http handler does not know how to handle #{obj.class.name}"
      end
      begin
        # At some point add a field to the Model to tell whether
        # the endpoint is trusted, otherwise just assume that everything talking
        # via https needs to use a trusted client with peer cert verification.
        if meth == "https"
          TrustedClient.new(endpoint).post(data.to_json)
        else
          RestClient::Request.execute(
            method: :post,
            url: endpoint,
            timeout: 1,
            payload: data.to_json,
            headers: {
              content_type: 'application/json',
              accept: 'application/json'
            })
        end
      rescue => e
        Rails.logger.error("EventSink: error POSTing back to #{endpoint}: #{e.inspect}")
      end
    else
      raise "Event handling method #{method} not implemented"
    end
  end

  private

  def check_endpoint_sanity
    method, sep, rest  = endpoint.partition('://')
    errors.add("Malformed endpoint #{endpoint}") if sep != '://'
    case method
    when 'http','https' then true
    when 'inproc' then
      objklass, _, methpart = rest.partition(':')
      case objklass
      when 'role'
        objname, _ ,methname = methpart.partition('/')
        runobj = (Role.find_key(objname) rescue nil)
        if runobj
          meth_sym = methname.to_sym
          unless runobj.respond_to?(meth_sym)
            errors.add("Role #{objname} does not respond to #{methname}")
          end
        else
          errors.add("No such role #{objname}")
        end
      else
        errors.add("inproc:// only handles roles for now")
      end
    else
      errors.add("Event handling method #{method} not supported yet")
    end
  end


end
