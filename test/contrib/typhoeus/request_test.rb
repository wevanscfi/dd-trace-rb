require 'time'
require 'contrib/typhoeus/test_helper'
require 'ddtrace'
require 'helper'
require 'json'
require 'pry'

class TyphoeusRequestTest < Minitest::Test
  ELASTICSEARCH_HOST = '127.0.0.1'.freeze
  ELASTICSEARCH_PORT = 49200
  ELASTICSEARCH_SERVER = "#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT.to_s}/"

  def setup
    @tracer = get_test_tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server 'http://' + ELASTICSEARCH_HOST + ':' + ELASTICSEARCH_PORT.to_s, 60
  end

  def test_get_request
    request = ::Typhoeus::Request.new("#{ELASTICSEARCH_SERVER}_cluster/health")
    pin = ::Datadog::Pin.get_from(request)
    pin.tracer = @tracer

    response = request.run
    assert_equal(200, response.code, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('typhoeus', span.service)
    assert_equal('GET', span.resource)
    assert_equal("/_cluster/health", span.get_tag('http.uri'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal(0, span.status, 'this should not be an error')
  end

  def test_post_request
    request = ::Typhoeus::Request.new("#{ELASTICSEARCH_SERVER}my/thing/42", method: :post, body: '{ "foo": "bar" }')
    pin = ::Datadog::Pin.get_from(request)
    pin.tracer = @tracer

    response = request.run
    assert_operator(200, :<=, response.code.to_i, 'bad response status')
    assert_operator(201, :>=, response.code.to_i, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('typhoeus', span.service)
    assert_equal('POST', span.resource)
    assert_equal('/my/thing/42', span.get_tag('http.uri'))
    assert_equal('POST', span.get_tag('http.method'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('49200', span.get_tag('out.port'))
    assert_equal(0, span.status, 'this should not be an error')
  end

  def test_404
    request = ::Typhoeus::Request.new("#{ELASTICSEARCH_SERVER}admin.php", params: { user: 'admin', passwd: '123456' })
    pin = ::Datadog::Pin.get_from(request)
    pin.tracer = @tracer

    response = request.run
    assert_equal(404, response.code, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('typhoeus', span.service)
    assert_equal('GET', span.resource)
    assert_equal('/admin.php', span.get_tag('http.uri'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('404', span.get_tag('http.status_code'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('49200', span.get_tag('out.port'))
    assert_equal(1, span.status, 'this should be an error (404)')
    assert_equal('Typhoeus::Errors::TyphoeusError', span.get_tag('error.type'))
  end

  def test_pin_override
    request = ::Typhoeus::Request.new("#{ELASTICSEARCH_SERVER}_cluster/health")
    pin = ::Datadog::Pin.get_from(request)
    pin.tracer = @tracer

    pin.service = 'bar'

    response = request.run
    assert_equal(200, response.code, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('bar', span.service)
  end
end
