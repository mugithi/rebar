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
#
class AttribsController < ApplicationController
  self.model = Attrib
  self.cap_base = "ATTRIB"

  def index
    model.transaction do
      target = find_target("READ")
      @list = if target.nil?
                # Global attribs are read-able by
                model.all
              else
                target.attribs.map do |i|
                  e = i.as_json
                  e["value"] = i.get(target)
                  e
                end
              end
    end
    respond_to do |format|
      format.html { }
      format.json { render api_index model, @list }
    end
  end

  def show
    ret = nil
    bucket = params[:bucket] ? params[:bucket].to_sym : :all
    model.transaction do
      target = find_target("READ")
      @attrib = model.find_key params[:id]
      ret = @attrib.as_json
      if target
        ret["value"] = @attrib.get(target,bucket)
        ret["node_id"] = target.is_a?(Node) ? target.id : nil
      end
    end
    respond_to do |format|
      format.html { }
      format.json { render json: ret, content_type: cb_content_type(@attrib, "obj") }
    end
  end

  def create
    model.transaction do
      validate_create
      params[:barclamp_id] = Barclamp.find_key(params[:barclamp]).id if params.has_key? :barclamp
      params[:role_id] =  Role.find_key(params[:role]).id if params.has_key? :role
      params.require(:name)
      params.require(:barclamp_id)
      @attrib = Attrib.create!(params.permit(:name,
                                             :barclamp_id,
                                             :role_id,
                                             :type,
                                             :description,
                                             :writable,
                                             :schema,
                                             :order,
                                             :map))
    end
    render api_show @attrib
  end

  def update
    # unpack form updates
    bucket = params[:bucket] ? params[:bucket].to_sym : :user
    if bucket != :user && bucket != :note
      render api_not_supported 'put', 'attribs/:id'
      return
    end
    ret = Hash.new
    attrib = nil
    Attrib.transaction do
      attrib = model.find_key(params[:id])
      target = find_target("UPDATE")
      if target.nil?
        # Target is nil because we didn't have a specifier (not found throws an exception)
        # Try to update the actual attribute object
        attrib = find_key_cap(model,params[:id],cap("UPDATE")).lock!
        simple_update(attrib, %w{default map description order schema role_id barclamp_id name})
        render json: attrib.as_json, content_type: cb_content_type(attrib, "obj")
        return
      end
      target.lock!
      val = nil
      if request.patch?
        current_attrib = attrib.as_json
        current_attrib["value"]=attrib.get(target)
        Rails.logger.debug("patch_attrib: starting with #{current_attrib["value"].inspect}")
        Rails.logger.debug("patch_attrib: patch: #{request.raw_post}")
        val = JSON::Patch.new(current_attrib,JSON.parse(request.raw_post)).call["value"]
        Rails.logger.debug("patch attrib: patched to #{val}")
      else
        params[:value] = params[:attrib][:value] if params[:attrib]
        params.require(:value)
        params[:value] = params[:value].to_i if attrib.schema['type'] == 'int'
        val = params["value"]
      end
      Rails.logger.debug("update_attrib: saving #{val} to #{target.class.name}:#{target.uuid}")
      attrib.set(target,val, bucket)
      flash[:notice] = I18n.t('commit_required', :role => target.name)
      ret = attrib.as_json
      ret["value"] = val
    end
    render json: ret, content_type: cb_content_type(attrib, "obj")
  end

  def destroy
    model.transaction do
      @attrib = find_key_cap(model,params[:id] || params[:name], cap("DESTROY"))
      @attrib.destroy
    end
    render api_delete @attrib
  end

  private

  def find_target(action)
    m,k,c = case
            when params.has_key?(:node_id)
              [Node, params[:node_id], "NODE"]
            when params.has_key?(:role_id)
              [Role, params[:role_id], "ROLE"]
            when params.has_key?(:node_role_id)
              [NodeRole, params[:node_role_id], "NODE"]
            when params.has_key?(:deployment_id)
              [Deployment, params[:deployment_id], "DEPLOYMENT"]
            when params.has_key?(:deployment_role_id)
              [DeploymentRole, params[:deployment_role_id], "DEPLOYMENT"]
            else
              return nil
            end
    find_key_cap(m,k,cap(action,c))
  end
end
