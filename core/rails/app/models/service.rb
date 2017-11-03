# Copyright 2015, Greg Althaus
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

class Service < Role

  after_create      :load_uuid

  def load_uuid
    self.reload
  end

  private :load_uuid
  
  def wait_for_service(nr,data,service_name)
    runlog = []
    runlog << "Getting #{service_name} information from consul"
    pieces = nil
    options = {}
    meta = {}
    count=0
    while pieces.nil? || pieces.empty?
      begin
        count += 1
        break if count > 20
        pieces = ConsulAccess.getService(service_name, :all, options, meta)
        if pieces == nil
          Rails.logger.info("#{service_name} not found ... wait 10s")
          runlog << "#{service_name} not found ... wait 10s"
          sleep 10
          next
        end
        pieces.select! do |piece|
          # New-school method of seeing if this service is in the proper deployment
          # Ignore services with the "forward" tag, those are flags for the forwarder.
          !piece.ServiceTags.any?{|st|st == "forward"} &&
            piece.ServiceTags.any? do |st|
            st =~ /^deployment:\s?#{nr.deployment.name}$/ || st == nr.deployment.name
          end
        end
        if pieces.empty?
          Rails.logger.info("#{service_name} not available ... wait 10m or next update")
          runlog << "#{service_name} not available ... wait 10m or next update"
          if meta[:index]
            options[:wait] = "10m"
            count -= 1 if options[:index] and options[:index] < meta[:index] # Don't count an update as a timeout
            options[:index] = meta[:index]
          else
            sleep 10
          end
          next
        end
      rescue StandardError => e
        runlog << "Failed to talk to consul: #{e.message}"
        Rails.logger.info("Failed to talk to consul: #{e.message}")
        sleep 10
      end
    end
    return [runlog,pieces]
  end

  # An option block can be given to format the service for return in the attribute
  def internal_do_transition(nr, data, service_name, service_attribute)

    runlog, pieces = wait_for_service(nr,data,service_name)
    addr_arr = []

    runlog << "Processing pieces for #{service_name}"
    NodeRole.transaction do
      if pieces
        pieces.each do |p|
          if block_given?
            addr_arr << yield(p)
          else
            addr = p.ServiceAddress
            addr = p.Address if addr.nil? or addr.empty?
            addr_arr << addr
          end
        end
        runlog << "Setting #{service_name} attribute"
        Attrib.set(service_attribute, nr, addr_arr, :system)
      end

      Rails.logger.info("Finished waiting for #{service_name}: #{addr_arr.length} found")
      nr.runlog = runlog.join("\n")
      nr.save!
    end
    raise "#{service_name} not available" if pieces == nil or pieces.empty?
  end

end
