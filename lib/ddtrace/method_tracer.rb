require 'pry'

module Datadog
  # A module for adding method tracer functionality
  module MethodTracer
    def self.included base
      base.extend ClassMethods
    end

    module ClassMethods
      # Create the datadog pin with
      # non-default meta data options
      #
      # @param [String] service
      # @param [Hash] options
      # @options[:app] [String]
      # @options[:tags] [Hash]
      # @options[:app_type] [String]
      # @options[:tracer] [Datadog::Tracer]
      def datadog_pin_options(service, options = {})
        @@datadog_pin_options = [service, options]
      end

      # Return a datadog pin
      # created with the class options
      #
      # @return [Datadog::Pin]
      def create_datadog_pin
        Datadog::Pin.new(*get_pin_options)
      end

      # Return this classes pin options
      #
      # @return [Hash] options
      def get_pin_options
        @@datadog_pin_options || nil
      end

      # Create a new method that encapsulates
      # the passed method in a datadog trace span
      #
      # Alias the old method to _untraced_method to allow it
      # to still be called
      #
      # Alias the traced method to the original method name
      #
      # @param [Symbol] method name
      def trace_method(method_name, options = {tags: []})
        begin
          traced_method = _traced_method_name(method_name)
          untraced_method = _untraced_method_name(method_name)
          resource = resource_name(method_name)
          # Raise an error if the traced or untraced methods
          # already exist
          if method_present?(traced_method) || method_present?(untraced_method)
            raise "Traced Method Already Exists #{resource}"
          end

          # Create the new traced method
          define_method(traced_method) do
            trace_pin.trace(resource) do |span|
              options[:tags].each { |k, v| span.set_tag(k, v) } unless options[:tags].empty?
              self.send(untraced_method)
            end
          end

          alias_method _untraced_method_name(method_name), method_name
          alias_method method_name, _traced_method_name(method_name)
        rescue StandardError => error
          Datadog::Tracer.log.debug "Unable to create traced method: #{error}"
        end
      end

      private
      # Check if a method or private method
      # exists
      #
      # @param [Symbol] method_name
      #
      # @return [Bool]
      def method_present?(method_name)
        method_defined?(method_name) || private_method_defined?(method_name)
      end

      # Return an untraced method name
      #
      # @param [Symbol] method name
      def _untraced_method_name(name)
        "_untraced_#{name}".to_sym
      end

      # Return a traced method name
      #
      # @param [Symbol] method name
      def _traced_method_name(name)
        "_traced_#{name}".to_sym
      end

      # Return the full class + method name
      #
      # @param [Symbol, String] method_name
      #
      # @return [String]
      def resource_name(method_name)
        "#{self.name}##{method_name}"
      end
    end

    # Lazy initialize the datadog pin
    #
    # @return [Datadog::Pin]
    def trace_pin
      @datadog_pin ||= self.class.create_datadog_pin
    end
  end
end
