require 'helper'
require 'ddtrace'
require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'benchmark'
require 'pry'

class PinTest < Minitest::Test
  def test_pin_onto
    a = '' # using String, but really, any object should fit

    pin = Datadog::Pin.new('abc', app: 'anapp')
    assert_equal('abc', pin.service)
    assert_equal('anapp', pin.app)
    pin.onto(a)

    got = Datadog::Pin.get_from(a)
    assert_equal('abc', got.service)
    assert_equal('anapp', got.app)

    assert_includes(got.tracer.services, 'abc', 'Service info for pin not set')
  end

  def test_pin_get_from
    a = [0, nil, self] # get_from should be callable on anything

    a.each do |x|
      assert_nil(Datadog::Pin.get_from(x))
    end
  end

  def test_to_s
    pin = Datadog::Pin.new('abc', app: 'anapp', app_type: 'db')
    assert_equal('abc', pin.service)
    assert_equal('anapp', pin.app)
    assert_equal('db', pin.app_type)
    repr = pin.to_s
    assert_equal('Pin(service:abc,app:anapp,app_type:db,name:)', repr)
  end

  def test_pin_accessor
    a = '' # using String, but really, any object should fit

    pin = Datadog::Pin.new('abc')
    pin.onto(a)

    got = a.datadog_pin
    assert_equal('abc', got.service)
  end

  def test_enabled
    pin = Datadog::Pin.new('abc')
    assert_equal(true, pin.enabled?)
  end

  def test_trace
    writer = FauxWriter.new()
    tracer = Datadog::Tracer.new(writer: writer)
    pin = Datadog::Pin.new('abc', tracer: tracer)
    pin.trace('resource').finish
    pin.tracer.trace('trace_resource').finish
    spans = writer.spans()
    assert_equal(2, spans.length)
    span = spans[0]
    assert_equal('abc', span.service, 'Tracing from a pin, should use the pins service')
    span = spans[1]
    assert_equal('rake_test_loader', span.service, 'Tracing from the tracer, should use the default service')
  end
end
