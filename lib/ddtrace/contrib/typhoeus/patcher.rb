# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module Typhoeus
      SERVICE = 'typhoeus'.freeze

      # Patcher enables patching of 'tyohoeus' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        @patched = false

        module_function

        # patch applies our patch if needed
         def patch
          if !@patched && (defined?(::Typhoeus::VERSION) && \
                           Gem::Version.new(::Typhoeus::VERSION) >= Gem::Version.new('0.7.0'))
            begin
              # do not require these by default, but only when actually patching
              require 'ddtrace/monkey'
              require 'ddtrace/ext/app_types'
              require 'ddtrace/ext/typhoeus'
              require 'ddtrace/contrib/typhoeus/tags'

              patch_typhoeus()

              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Typhoeus integration: #{e}")
            end
          end
          @patched
        end

        def patch_typhoeus
          ::Typhoeus::Request.module_eval do
            alias_method :initialize_wihtout_datadog, :initialize
            ::Datadog::Monkey.without_warnings do
              remove_method :initialize
            end

            def initialize(*args)
              pin = ::Datadog::Pin.new(SERVICE, app: 'typhoeus', app_type: Datadog::Ext::AppTypes::WEB)
              pin.onto(self)
              if pin.tracer && pin.service
                pin.tracer.set_service_info(pin.service, pin.app, pin.app_type)
              end
              initialize_wihtout_datadog(*args)
            end
          end

          ::Typhoeus.before do |request|
            pin = ::Datadog::Pin.get_from(request)
            span = pin.tracer.trace('web_external',
              service: pin.service,
              span_type: ::Datadog::Ext::Typhoeus::TYPE,
              resource: request.options[:method],
            )
            callback = Proc.new do
              ::Datadog::Contrib::Typhoeus::Tags.set_request_tags(request, span)
              span.finish()
            end
            request.on_complete.unshift(callback)

            # before hook must return true
            true
          end
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
