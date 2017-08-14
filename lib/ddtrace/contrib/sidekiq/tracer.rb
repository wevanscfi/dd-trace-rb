require 'sidekiq/api'

require 'ddtrace/ext/app_types'

sidekiq_vs = Gem::Version.new(Sidekiq::VERSION)
sidekiq_min_vs = Gem::Version.new('4.0.0')
if sidekiq_vs < sidekiq_min_vs
  raise "sidekiq version #{sidekiq_vs} is not supported yet " \
        + "(supporting versions >=#{sidekiq_min_vs})"
end

Datadog::Tracer.log.debug("Activating instrumentation for Sidekiq '#{sidekiq_vs}'")

module Datadog
  module Contrib
    module Sidekiq
      DEFAULT_CONFIG = {
        enabled: true,
        sidekiq_service: 'sidekiq',
        tracer: Datadog.tracer,
        debug: false,
        trace_agent_hostname: Datadog::Writer::HOSTNAME,
        trace_agent_port: Datadog::Writer::PORT
      }.freeze

      # Middleware is a Sidekiq server-side middleware which traces executed jobs
      class Tracer
        def initialize(options = {})
          # check if Rails configuration is available and use it to override
          # Sidekiq defaults
          rails_config = ::Rails.configuration.datadog_trace rescue {}
          base_config = DEFAULT_CONFIG.merge(rails_config)
          user_config = base_config.merge(options)
          @tracer = user_config[:tracer]
          @sidekiq_service = user_config[:sidekiq_service]

          # set Tracer status
          @tracer.enabled = user_config[:enabled]
          Datadog::Tracer.debug_logging = user_config[:debug]

          # configure the Tracer instance
          @tracer.configure(
            hostname: user_config[:trace_agent_hostname],
            port: user_config[:trace_agent_port]
          )
        end

        def call(worker, job, queue)
          # If class is wrapping something else, the interesting resource info
          # is the underlying, wrapped class, and not the wrapper.
          resource = if job['wrapped']
                       job['wrapped']
                     else
                       job['class']
                     end

          # configure Sidekiq service
          service = sidekiq_service(resource_worker(resource))
          set_service_info(service)

          queued_time = Time.strptime(job['enqueued_at'].to_s, '%s.%L')

          @tracer.trace('sidekiq.queue',
                        service: service,
                        span_type: 'job',
                        start_time: queued_time) do |span|
            span.resource = job['queue']
          end

          @tracer.trace('sidekiq.job', service: service, span_type: 'job') do |span|
            span.resource = resource
            span.set_tag('sidekiq.job.id', job['jid'])
            span.set_tag('sidekiq.job.retry', job['retry'])
            span.set_tag('sidekiq.job.queue', job['queue'])
            span.set_tag('sidekiq.job.wrapper', job['class']) if job['wrapped']

            yield
          end
        end

        private

        # rubocop:disable Lint/HandleExceptions
        def resource_worker(resource)
          Object.const_get(resource)
        rescue NameError
        end

        def worker_config(worker)
          if worker.respond_to?(:datadog_tracer_config)
            worker.datadog_tracer_config
          else
            {}
          end
        end

        def sidekiq_service(resource)
          worker_config(resource).fetch(:service, @sidekiq_service)
        end

        def set_service_info(service)
          return if @tracer.services[service]
          @tracer.set_service_info(
            service,
            'sidekiq',
            Datadog::Ext::AppTypes::WORKER
          )
        end
      end
    end
  end
end
