require 'helper'
require 'ddtrace'
require 'benchmark'

class TestClass
  include Datadog::MethodTracer
  writer = FauxWriter.new()
  tracer = Datadog::Tracer.new(writer: writer)

  datadog_pin_options 'test-app', app: 'test-app', tags: {test: "me out"}, tracer: tracer

  def test_method
    'Test return'
  end
  trace_method :test_method, tags: { second_tag: "is set" }

  def second_method
    'Second return'
  end
  trace_method :second_method
  # Checking to make sure that
  # calling trace_method twice
  # does not break anything
  # It should only log to the
  # debugger
  trace_method :second_method
end

class MethodTracerIntegrationTest < Minitest::Test
  def setup
    @subject = TestClass.new
    @tracer = @subject.trace_pin.tracer
    @writer = @tracer.writer
  end

  def test_one_method_trace
    # assert that the original method can be called untraced
    # and return the expected results
    assert_equal('Test return', @subject.send(:_untraced_test_method))

    # assert that the new method can be called
    # creates a span
    # and returns the expected results
    assert_equal('Test return', @subject.send(:test_method))
    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]
    # assert the spans attributes are correct
    assert_equal(0, span.status)
    assert_equal('test-app', span.service)
    assert_equal('is set', span.get_tag(:second_tag))
    assert_equal('TestClass#test_method', span.resource)
  end

  def test_second_method_trace
    # assert that the original method can be called untraced
    # and return the expected results
    assert_equal('Second return', @subject.send(:_untraced_second_method))

    # assert that the new method can be called
    # creates a span
    # and returns the expected results
    assert_equal('Second return', @subject.send(:second_method))

    spans = @writer.spans()
    assert_equal(1, spans.length)

    span = spans[0]

    # assert the spans attributes are correct
    assert_equal(0, span.status)
    assert_equal('TestClass#second_method', span.resource)
    assert_equal('me out', span.get_tag(:test))
  end
end
