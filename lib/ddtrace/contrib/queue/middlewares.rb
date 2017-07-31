require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    # Queue module includes middleware that is used to calculate the
    # time a request spends waiting in a queue before being processed.
    #
    # @since 0.7.3
    module Queue
      # Request header set by upstream
      HTTP_HEADER_REQUEST_START = 'HTTP_X_REQUEST_START'.freeze

      # Middleware for adding a span to track request queued time
      #
      # @since 0.7.3
      #
      # @attr [Middleware] app call next in the middleware chain
      # @attr [Hash] options contains datadog configuration options
      # @attr [Object] tracer global data dog trace agent
      # @attr [String] service the data dog service trace name
      class TraceMiddleware
        DEFAULT_CONFIG = {
          tracer: Datadog.tracer,
          default_service: 'request_queue'
        }.freeze

        # Initialize
        #
        # @since 0.7.3
        #
        # @param [Middleware] app
        # @param [Hash] options
        # @options opts [Datadog::Tracer] :tracer
        # @options opts [String] :service
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

        # Parse the request queued at time from the header
        #
        # @since 0.7.3
        #
        # @param [String] request_start_header A string in the format `t=%s.%L`
        #
        # @return [Time] request queued at time, or now
        def parse_request_start_header(request_start_header)
          return Time.now if request_start_header.nil?
          Time.strptime(request_start_header, 't=%s.%L')
        rescue
          Time.now
        end

        # Method called by all middlewares on the next middleware in the chain
        #
        # @since 0.7.3
        #
        # @params [Hash] env
        # @return [Hash] results
        # @results [Fixnum] :status
        # @results [Rack::Utils::HeaderHash] :headers
        # @results [Rack::BodyProxy] :response
        def call(env)
          # configure the middleware once
          configure()

          # Create a span for tracking the time since the request was queued
          # Useful for tracking time spent in unicorn or puma before being passed to
          # a child worker
          request_queued = parse_request_start_header(env[Datadog::Contrib::Queue::HTTP_HEADER_REQUEST_START])
          @tracer.trace('request.queue',
                        service: @service,
                        span_type: Datadog::Ext::HTTP::TYPE,
                        start_time: request_queued,
                        resource: 'Request Queue'
                       ).finish()

          # call down the middleware stack
          status, headers, response = @app.call(env)
        ensure
          # ensure that we respond back up the stack
          [status, headers, response]
        end
      end
    end
  end
end
