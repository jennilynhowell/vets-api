# frozen_string_literal: true

module Appeals
  module Responses
    class Appeals < Common::Base
      attribute :body, String
      attribute :status, Integer

      def initialize(body, status)
        self.body = body if json_format_is_valid?(body)
        self.status = status
      rescue JSON::Schema::ValidationError => error
        raise Common::Client::Errors::ParsingError.new(error.message, 502)
      end

      private

      def json_format_is_valid?(body)
        JSON::Validator.validate!('lib/appeals/schema/appeals.json', body, strict: true)
      end
    end
  end
end
