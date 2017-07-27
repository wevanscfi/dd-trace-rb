require 'ddtrace/ext/http'
require 'ddtrace/ext/net'

module Datadog
  module Contrib
    module Typhoeus
      # Tags handles generic common tags assignment.
      module Tags
        module_function

        def set_request_tags(request, span)
          parsed = URI.parse(request.response.effective_url)
          span.set_tag Datadog::Ext::HTTP::URL, request.base_url
          span.set_tag Datadog::Ext::HTTP::METHOD, request.options[:method]
          span.set_tag Datadog::Ext::HTTP::STATUS_CODE,request.response.code
          span.set_tag Datadog::Ext::NET::TARGET_HOST, parsed.host
          span.set_tag Datadog::Ext::NET::TARGET_PORT, parsed.port

          case request.response.code.to_i / 100
          when 4
            span.set_error(request.response)
          when 5
            span.set_error(request.response)
          end
        ensure
          # ensure that we don't die here
          true
        end
      end
    end
  end
end
