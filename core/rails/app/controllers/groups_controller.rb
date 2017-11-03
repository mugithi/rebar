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
class GroupsController < ApplicationController
  self.model = Group
  self.cap_base = "GROUP"
  
  def index
    @list = if params.has_key? :node_id
              find_key_cap(Node, params[:node_id],cap("READ","NODE")).
                groups.visible(cap("READ"),@current_user.id)
            else
              visible(model, cap("READ"))
            end
    respond_to do |format|
      format.html { }
      format.json { render api_index Group, @list }
    end
  end

  def show
    @group = find_key_cap(model, params[:id], cap("READ"))
    respond_to do |format|
      format.html { }
      format.json { render api_show @group }
    end
  end
  
  def create
    params.require(:name)
    params[:category] = params[:category].first if params[:category].kind_of?(Array)
    params[:tenant_id] ||= @current_user.current_tenant_id
    Group.transaction do
      validate_create(params[:tenant_id])
      @group = Group.create! params.permit(:name, :description, :category, :tenant_id)
    end
    respond_to do |format|
      format.html { redirect_to group_path(@group.id)}
      format.json { render api_show @group }
    end
  end
  
  def update
    if params.has_key? :node_id
      Group.transaction do
        # Both of these should arguably be UPDATE
        @group = find_key_cap(model, params[:id], cap("UPDATE"))
        @node = find_key_cap(Node, params[:node_id], cap("READ","NODE"))
        @node.groups << @group
      end
      respond_to do |format|
        format.html { render :text=>I18n.t('api.added', :item=>@group.name, :collection=>'node.groups') }
        format.json { render api_show @node }
      end
      return
    end
    params[:category] = params[:category].first if params[:category].kind_of?(Array)
    Group.transaction do
      @group = find_key_cap(model,params[:id], cap("UPDATE"))
      simple_update(@group,%w(name description category tenant_id))
    end
    render api_show @group
  end

  def destroy
    if params.has_key? :node_id
      model.transaction do
        # Arguably, these should both be UPDATE
        @node = find_key_cap(Node, params[:node_id] , cap("READ","NODE"))
        @group = find_key_cap(model, params[:id], cap("UPDATE"))
        @group.nodes.delete(@node)
      end
      respond_to do |format|
        format.html { render :text=>I18n.t('api.removed', :item=>'node', :collection=>'group') }
        format.json { render api_delete @node }
      end
      return
    end
    model.transaction do
      @group = find_key_cap(model, params[:id], cap("DESTROY"))
      @group.destroy
    end
    render api_delete @group
  end

end
