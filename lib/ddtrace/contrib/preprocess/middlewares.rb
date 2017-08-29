require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    # Module includes middleware that is used to calculate the
    # time a request spends in other processes before being
    # processed by rack.
    #
    module Preprocess
      # Middleware for adding a span to track time spent in a preprocess
      # service
      #
      # @attr [Middleware] app call next in the middleware chain
      # @attr [Hash] options contains datadog configuration options
      # @attr [Object] tracer global data dog trace agent
      # @attr [String] service the data dog service trace name
      class TimingHeaderMiddleware
        DEFAULT_CONFIG = {
          tracer: Datadog.tracer,
          default_service: 'preprocess',
          app: 'request-server',
          app_type: Datadog::Ext::AppTypes::WEB,
          name: 'request.queue',
          timing_start_header: 'HTTP_X_REQUEST_START',
          timing_end_header: nil,
          header_format: 't=%s.%L'
        }.freeze

        # Initialize
        #
        # @param [Middleware] app
        # @param [Hash] options
        # @options opts [Datadog::Tracer] :tracer
        # @options opts [String] :service
        def initialize(app, options = {})
          @app = app
          @options = DEFAULT_CONFIG.merge(options)
          configure()
        end

        def configure
          # retrieve the current tracer and service
          @name = @options[:name]

          # Create and pin
          Datadog::Pin.new(
            @options[:service],
            app: @options[:app],
            app_type: @options[:app_type],
            tracer: @options[:tracer]
          ).onto(self)
        end

        # Parse the request queued at time from the header
        #
        # @param [String] request_start_header A string in the format `t=%s.%L`
        #
        # @return [Time] request queued at time, or now
        def parse_request_timing_header(request_start_header)
          return Time.now.utc if request_start_header.nil?
          Time.strptime(request_start_header, 't=%s.%L').utc
        rescue
          Time.now.utc
        end

        # Method called by all middlewares on the next middleware in the chain
        #
        # @params [Hash] env
        # @return [Hash] results
        # @results [Fixnum] :status
        # @results [Rack::Utils::HeaderHash] :headers
        # @results [Rack::BodyProxy] :response
        def call(env)
          # Create a span for tracking the time since the request was queued
          # Useful for tracking time spent in unicorn or puma before being passed to
          # a child worker
          start_header = env[@options[:timing_start_header]]
          end_header = env[@options[:timing_end_header]]
          upstream_started = parse_request_timing_header(start_header)
          upstream_ended = parse_request_timing_header(end_header)

          @datadog_pin.trace(
            @name,
            parent: nil,
            resource: nil, # Keep out of resource traces
            span_type: 'upstream',
            start_time: upstream_started,
          ).finish(upstream_ended)
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
