# Copyright 2015 RackN
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

class PacketProvider < CloudProvider

  before_save :inject_packet

  after_create      :load_uuid

  def load_uuid
    self.reload
  end

  private :load_uuid

  def self.template
    { 
      url: {
        type: "img",
        src: "https://www.packet.net/assets/images/logo-main.png",
        href: "https://packet.net",
        title: "Packet Host"
      },
      project_token: {
        type: "password",
        default: "",
        length: 30,
        name: I18n.t('token', scope: "providers.show.packet" )
      },
      project_id: {
        type: "text",
        default: "",
        length: 30,
        name: I18n.t('id', scope: "providers.show.packet" )
      },
      facility: {
        type: "text",
        default: "ewr1",
        length: 30,
        name: I18n.t('facility', scope: "providers.show.packet" )
      },
      plan: {
        type: "text",
        default: "baremetal_1",
        length: 30,
        name: I18n.t('plan', scope: "providers.show.packet" )
      },
      'provider-create-hint' => {
        type: "json_key",
        name: I18n.t('provider-create-hint', scope: "providers.show"),
        length: 3,
        default: {
          os: "centos_7"
        }
      }
    }
  end

  def variant_default
    'packet'
  end

  private

  def inject_packet
    auth_details['provider'] = 'Packet'
  end

end
