require 'time'

require 'ddtrace/utils'
require 'ddtrace/ext/errors'

module Datadog
  # Represents a logical unit of work in the system. Each trace consists of one or more spans.
  # Each span consists of a start time and a duration. For example, a span can describe the time
  # spent on a distributed call on a separate machine, or the time spent in a small component
  # within a larger operation. Spans can be nested within each other, and in those instances
  # will have a parent-child relationship.
  class Span
    # The max value for a \Span identifier
    MAX_ID = 2**64 - 1

    attr_accessor :name, :service, :resource, :span_type,
                  :start_time, :end_time,
                  :span_id, :trace_id, :parent_id,
                  :status, :parent, :sampled

    # Create a new span linked to the given tracer. Call the <tt>finish()</tt> method once the
    # tracer operation is over or use the <tt>finish_at(time)</tt> helper to close the span with the
    # given +time+. Available options are:
    #
    # * +service+: the service name for this span
    # * +resource+: the resource this span refers, or +name+ if it's missing
    # * +span_type+: the type of the span (such as +http+, +db+ and so on)
    # * +parent_id+: the identifier of the parent span
    # * +trace_id+: the identifier of the root span for this trace
    def initialize(tracer, name, options = {})
      @tracer = tracer

      @name = name
      @service = options.fetch(:service, nil)
      @resource = options.fetch(:resource, name)
      @span_type = options.fetch(:span_type, nil)

      @span_id = Datadog::Utils.next_id()
      @parent_id = options.fetch(:parent_id, 0)
      @trace_id = options.fetch(:trace_id, @span_id)

      @meta = {}
      @metrics = {}
      @status = 0

      @parent = nil
      @sampled = true

      @start_time = options.fetch(:start_time, Time.now.utc)
      @end_time = nil
    end

    # Set the given key / value tag pair on the span. Keys and values
    # must be strings. A valid example is:
    #
    #   span.set_tag('http.method', request.method)
    def set_tag(key, value)
      @meta[key] = value.to_s
    rescue StandardError => e
      Datadog::Tracer.log.debug("Unable to set the tag #{key}, ignoring it. Caused by: #{e}")
    end

    # Return the tag with the given key, nil if it doesn't exist.
    def get_tag(key)
      @meta[key]
    end

    # Set the given key / value metric pair on the span. Keys must be string.
    # Values must be floating point numbers.
    def set_metric(key, value)
      # enforce that the value is a floating point number
      value = Float(value)
      @metrics[key] = value
    rescue StandardError => e
      Datadog::Tracer.log.debug("Unable to set the metric #{key}, ignoring it. Caused by: #{e}")
    end

    # Return the metric with the given key, nil if it doesn't exist.
    def get_metric(key)
      @metrics[key]
    end

    # Mark the span with the given error.
    def set_error(e)
      return if e.nil?
      @status = 1
      @meta[Datadog::Ext::Errors::MSG] = e.message if e.respond_to?(:message) && e.message
      @meta[Datadog::Ext::Errors::TYPE] = e.class.to_s
      @meta[Datadog::Ext::Errors::STACK] = e.backtrace.join("\n") if e.respond_to?(:backtrace) && e.backtrace
    end

    # Mark the span finished at the current time and submit it.
    def finish(finish_time = nil)
      return if finished?

      @end_time = finish_time.nil? ? Time.now.utc : finish_time
      @tracer.record(self) unless @tracer.nil?
      self
    end

    # Proxy function that flag a span as finished with the given
    # timestamp. This function is used for retro-compatibility.
    # DEPRECATED: remove this function in the next release
    def finish_at(finish_time)
      finish(finish_time)
    end

    # Return whether the span is finished or not.
    def finished?
      !@end_time.nil?
    end

    # Return a string representation of the span.
    def to_s
      "Span(name:#{@name},sid:#{@span_id},tid:#{@trace_id},pid:#{@parent_id})"
    end

    # Set this span's parent, inheriting any properties not explicitly set.
    # If the parent is nil, set the span zero values.
    def set_parent(parent)
      @parent = parent

      if parent.nil?
        @trace_id = @span_id
        @parent_id = 0
      else
        @trace_id = parent.trace_id
        @parent_id = parent.span_id
        @service ||= parent.service
      end
    end

    # Return the hash representation of the current span.
    def to_hash
      h = {
        span_id: @span_id,
        parent_id: @parent_id,
        trace_id: @trace_id,
        name: @name,
        service: @service,
        resource: @resource,
        type: @span_type,
        meta: @meta,
        metrics: @metrics,
        error: @status
      }

      if !@start_time.nil? && !@end_time.nil?
        h[:start] = (@start_time.to_f * 1e9).to_i
        h[:duration] = ((@end_time - @start_time) * 1e9).to_i
      end

      h
    end

    # Return a human readable version of the span
    def pretty_print(q)
      start_time = (@start_time.to_f * 1e9).to_i rescue '-'
      end_time = (@end_time.to_f * 1e9).to_i rescue '-'
      duration = ((@end_time - @start_time) * 1e9).to_i rescue 0
      q.group 0 do
        q.breakable
        q.text "Name: #{@name}\n"
        q.text "Span ID: #{@span_id}\n"
        q.text "Parent ID: #{@parent_id}\n"
        q.text "Trace ID: #{@trace_id}\n"
        q.text "Type: #{@span_type}\n"
        q.text "Service: #{@service}\n"
        q.text "Resource: #{@resource}\n"
        q.text "Error: #{@status}\n"
        q.text "Start: #{start_time}\n"
        q.text "End: #{end_time}\n"
        q.text "Duration: #{duration}\n"
        q.group(2, 'Tags: [', "]\n") do
          q.breakable
          q.seplist @meta.each do |key, value|
            q.text "#{key} => #{value}"
          end
        end
        q.group(2, 'Metrics: [', ']') do
          q.breakable
          q.seplist @metrics.each do |key, value|
            q.text "#{key} => #{value}"
          end
        end
      end
    end
  end
end
