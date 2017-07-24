require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/distributed'

module Datadog
  module Contrib
    # Rack module includes middlewares that are required to trace any framework
    # and application built on top of Rack.
    module Rack
      # RACK headers to test when doing distributed tracing.
      # They are slightly different from real headers as Rack uppercases everything

      # Header used to transmit the trace ID.
      HTTP_HEADER_TRACE_ID = 'HTTP_X_DATADOG_TRACE_ID'.freeze

      # Header used to transmit the parent ID.
      HTTP_HEADER_PARENT_ID = 'HTTP_X_DATADOG_PARENT_ID'.freeze

      # Header used to transmit the request start time.
      HTTP_HEADER_REQUEST_START = 'HTTP_X_REQUEST_START'.freeze

      # TraceMiddleware ensures that the Rack Request is properly traced
      # from the beginning to the end. The middleware adds the request span
      # in the Rack environment so that it can be retrieved by the underlying
      # application. If request tags are not set by the app, they will be set using
      # information available at the Rack level.
      class TraceMiddleware
        DEFAULT_CONFIG = {
          tracer: Datadog.tracer,
          default_service: 'rack',
          distributed_tracing_enabled: false
        }.freeze

        def initialize(app, options = {})
          # update options with our configuration, unless it's already available
          [:tracer, :default_service, :distributed_tracing_enabled].each do |k|
            options[k] ||= DEFAULT_CONFIG[k]
          end

          @app = app
          @options = options
        end

        def configure
          # ensure that the configuration is executed only once
          return if @tracer && @service

          # retrieve the current tracer and service
          @tracer = @options.fetch(:tracer)
          @service = @options.fetch(:default_service)
          @distributed_tracing_enabled = @options.fetch(:distributed_tracing_enabled)

          # configure the Rack service
          @tracer.set_service_info(
            @service,
            'rack',
            Datadog::Ext::AppTypes::WEB
          )
        end

        def parse_request_start_header(request_start_header)
          return nil if request_start_header.nil?
          request_start = request_start_header.to_i
          if request_start.zero?
            Datadog::Tracer.log.debug("invalid request start header: #{request_start_header}")
            return nil
          end
          queue_time = Time.now.to_i - request_start
          if queue_time < 0
            Datadog::Tracer.log.debug("request start header out of range: #{request_start_header}")
            return nil
          end
          queue_time
        end

        # rubocop:disable Metrics/MethodLength
        def call(env)
          # configure the Rack middleware once
          configure()

          trace_options = {
            service: @service,
            resource: nil,
            span_type: Datadog::Ext::HTTP::TYPE
          }

          # start a new request span and attach it to the current Rack environment;
          # we must ensure that the span `resource` is set later
          request_span = @tracer.trace('rack.request', trace_options)

          if @distributed_tracing_enabled
            # Merge distributed trace ids if present
            #
            # Use integer values for tests, as it will catch both
            # a non-existing header or a badly formed one.
            trace_id, parent_id = Datadog::Distributed.parse_trace_headers(
              env[Datadog::Contrib::Rack::HTTP_HEADER_TRACE_ID],
              env[Datadog::Contrib::Rack::HTTP_HEADER_PARENT_ID]
            )
            request_span.trace_id = trace_id unless trace_id.nil?
            request_span.parent_id = parent_id unless parent_id.nil?
          end

          request_queueing = parse_request_start_header(env[Datadog::Contrib::Rack::HTTP_HEADER_REQUEST_START])
          request_span.set_tag('queueing', request_queueing) unless request_queueing.nil?

          env[:datadog_rack_request_span] = request_span

          # call the rest of the stack
          status, headers, response = @app.call(env)
        # rubocop:disable Lint/RescueException
        # Here we really want to catch *any* exception, not only StandardError,
        # as we really have no clue of what is in the block,
        # and it is user code which should be executed no matter what.
        # It's not a problem since we re-raise it afterwards so for example a
        # SignalException::Interrupt would still bubble up.
        rescue Exception => e
          # catch exceptions that may be raised in the middleware chain
          # Note: if a middleware catches an Exception without re raising,
          # the Exception cannot be recorded here
          request_span.set_error(e)
          raise e
        ensure
          # the source of truth in Rack is the PATH_INFO key that holds the
          # URL for the current request; some framework may override that
          # value, especially during exception handling and because of that
          # we prefer using the `REQUEST_URI` if this is available.
          # NOTE: `REQUEST_URI` is Rails specific and may not apply for other frameworks
          url = env['REQUEST_URI'] || env['PATH_INFO']

          # Rack is a really low level interface and it doesn't provide any
          # advanced functionality like routers. Because of that, we assume that
          # the underlying framework or application has more knowledge about
          # the result for this request; `resource` and `tags` are expected to
          # be set in another level but if they're missing, reasonable defaults
          # are used.
          request_span.resource = "#{env['REQUEST_METHOD']} #{status}".strip unless request_span.resource
          if request_span.get_tag(Datadog::Ext::HTTP::METHOD).nil?
            request_span.set_tag(Datadog::Ext::HTTP::METHOD, env['REQUEST_METHOD'])
          end
          if request_span.get_tag(Datadog::Ext::HTTP::URL).nil?
            request_span.set_tag(Datadog::Ext::HTTP::URL, url)
          end
          if request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE).nil? && status
            request_span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, status)
          end

          # detect if the status code is a 5xx and flag the request span as an error
          # unless it has been already set by the underlying framework
          if status.to_s.start_with?('5') && request_span.status.zero?
            request_span.status = 1
            # in any case we don't touch the stacktrace if it has been set
            if request_span.get_tag(Datadog::Ext::Errors::STACK).nil?
              request_span.set_tag(Datadog::Ext::Errors::STACK, caller().join("\n"))
            end
          end

          request_span.finish()

          [status, headers, response]
        end
      end
    end
  end
end
