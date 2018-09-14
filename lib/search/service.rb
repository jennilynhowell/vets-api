# frozen_string_literal: true

require 'common/client/base'
require 'search/response'

module Search
  class Service < Common::Client::Base
    include Common::Client::Monitoring

    STATSD_KEY_PREFIX = 'api.search'

    configuration Search::Configuration

    attr_reader :query

    def initialize(query)
      @query = query
    end

    # GETs a list of search results from Search.gov web results API
    # @return [Search::ResultsResponse] wrapper around results data
    #
    def results
      with_monitoring do
        response = perform(:get, results_url, query_params)
        Search::ResultsResponse.from(response)
      end
    rescue StandardError => error
      handle_error(error)
    end

    private

    def results_url
      config.base_path
    end

    # Required params [affiliate, access_key, query]
    # Optional params [enable_highlighting, limit, offset, sort_by]
    #
    # @see https://search.usa.gov/sites/7378/api_instructions
    #
    def query_params
      {
        affiliate:  affiliate,
        access_key: access_key,
        query:      query
      }
    end

    def affiliate
      Settings.search.affiliate
    end

    def access_key
      Settings.search.access_key
    end

    def handle_error(error)
      case error
      when Common::Client::Errors::ClientError
        log_error_message(error)
        return ResultsResponse.new(400, body: error.message) if error.status == 400
      else
        raise error
      end
    end

    def log_error_message(error)
      log_message_to_sentry(
        error.message,
        :error,
        { url: config.base_path },
        search: 'search_results_query_error'
      )
    end
  end
end
