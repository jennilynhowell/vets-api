# frozen_string_literal: true
module EVSS
  module GiBillStatus
    class Configuration < EVSS::Configuration
      def base_path
        "#{Settings.evss.url}/wss-education-services-web/rest/education/chapter33/v1"
      end

      def service_name
        'EVSS/GiBillStatus'
      end
    end
  end
end
