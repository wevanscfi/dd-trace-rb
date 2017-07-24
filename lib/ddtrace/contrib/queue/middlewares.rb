require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    # Queue module includes middlewares that are used to calculate the
    # time a request spends waiting in a queue before being processed.
    module Queue
      # Header used to set the time requests are queued
      HTTP_HEADER_REQUEST_START = 'HTTP_X_REQUEST_START'.freeze

      class TraceMiddleware
        DEFAULT_CONFIG = {
          tracer: Datadog.tracer,
          default_service: 'request_queue'
        }.freeze

        def initialize(app, options = {})
          # update options with our configuration, unless it's already available
          options[:tracer] ||= DEFAULT_CONFIG[:tracer]
          options[:default_service] ||= DEFAULT_CONFIG[:default_service]

          @app = app
          @options = options
        end

        def configure
          # ensure that the configuration is executed only once
          return if @tracer && @service

          # retrieve the current tracer and service
          @tracer = @options.fetch(:tracer)
          @service = @options.fetch(:default_service)

          # configure the Queue service
          @tracer.set_service_info(
            @service,
            'request_queue',
            Datadog::Ext::AppTypes::WEB
          )
        end

        def parse_request_start_header(request_start_header)
          return Time.now if request_start_header.nil?
          # Expect the REQUEST_START header in the format `t=%s.%L`
          Time.strptime(request_start_header, 't=%s.%L')
        end

        def call(env)
          # configure the middleware once
          configure()

          # Default options to start a span with
          trace_options = {
            service: @service,
            resource: nil,
            span_type: Datadog::Ext::HTTP::TYPE
          }

          # Create a span for tracking the time since the request was queued
          # Useful for tracking time spent in unicorn or puma before being passed to
          # a child worker
          #
          # Set header `HTTP_X_REQUEST_START` in nginx prior to sending upstream
          request_queued = parse_request_start_header(env[Datadog::Contrib::Rack::HTTP_HEADER_REQUEST_START])
          @tracer.trace('request.queue', trace_options.merge(
            start_time: request_queued,
            resource: 'Request Queue'
          )).finish()

          binding.pry

          status, headers, response = @app.call(env)
        rescue StandardError => e
          # catch exceptions that may be raised in the middleware chain
          # Note: if a middleware catches an Exception without re raising,
          # the Exception cannot be recorded here
          request_span.set_error(e)
          raise e
        ensure
          # ensure we return up the chain
          [status, headers, response]
        end
      end
    end
  end
end
