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

require 'securerandom'

class Event
  
  def self.fire(obj, params)
    Rails.logger.info("Event: event fired with params #{params.to_json}")
    # This handles * and missing selectors (assumed to be true) - more could be done
    wherefrags = []
    params.each do |k,v|
      wherefrags << "(((event_selectors.selector ->> '#{k.to_s}') IS NULL) OR (event_selectors.selector @> '#{ {k.to_s => v}.to_json }'::jsonb))"
    end
    res = []
    evt = {params: params,
           uuid: SecureRandom.uuid,
           target_class: obj.class.name,
           target: obj.as_json}
    EventSelector.where(wherefrags.join(" AND ")).order(:id).distinct.each do |ms|
      es = ms.event_sink
      Rails.logger.info("Event: #{params} matched #{ms.selector}")
      Rails.logger.info("Event: calling #{es.endpoint} for #{ms.selector}")
      res << es.run(evt, obj, ms.selector)
    end
    return res
  end
end
