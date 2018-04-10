# frozen_string_literal: true

require 'common/client/base'

module Vet360
  class Service < Common::Client::Base
    STATSD_KEY_PREFIX = 'api.vet360'

    def initialize(user)
      @user = user
    end

    def perform(method, path, body = nil, headers = {})
      config.base_request_headers.merge(headers)
      super(method, path, body, headers)
    end

    private

    # TODO - update backend exception params from EVSS to Vet360
    # TODO - perhaps abstract this into a common class for EVSS, Vet360, etc.
    def handle_error(error)
      case error
      when Faraday::ParsingError
        log_message_to_sentry(error.message, :error, extra_context: { url: config.base_path })
        raise_backend_exception('EVSS502', self.class)
      when Common::Client::Errors::ClientError
        raise Common::Exceptions::Forbidden if error.status == 403
        log_message_to_sentry(error.message, :error, extra_context: { url: config.base_path, body: error.body })
        raise_backend_exception('EVSS400', self.class, error) if error.status == 400
        raise_backend_exception('EVSS502', self.class, error)
      else
        raise error
      end
    end

    # TODO - update backend exceptions from EVSS to Vet360
    # TODO - perhaps abstract this into a common class for EVSS, Vet360, etc.
    def raise_backend_exception(key, source, error = nil)
      raise Common::Exceptions::BackendServiceException.new(
        key,
        { source: "#{source}" },
        error&.status,
        error&.body
      )
    end
  end
end
