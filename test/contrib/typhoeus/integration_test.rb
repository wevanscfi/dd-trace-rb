require 'time'
require 'helper'

class TyphoeusIntegrationTest < Minitest::Test
  ELASTICSEARCH_HOST = '127.0.0.1'.freeze
  ELASTICSEARCH_PORT = 49200.freeze
  ELASTICSEARCH_SERVER = "#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT.to_s}".freeze

  def setup
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # Here we use the default tracer (to make a real integration test)
    @tracer = Datadog.tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server 'http://' + ELASTICSEARCH_HOST + ':' + ELASTICSEARCH_PORT.to_s, 60
  end

  def test_request
    sleep(1.5) # make sure there's nothing pending
    already_flushed = @tracer.writer.stats[:traces_flushed]
    response = ::Typhoeus.get(ELASTICSEARCH_SERVER + '/_cluster/health')
    assert_equal(200, response.code, 'bad response status')
    assert_kind_of(String, response.body)
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= already_flushed + 1
      sleep(0.1)
    end
    assert_equal(already_flushed + 1, @tracer.writer.stats[:traces_flushed])
  end

  def test_hydra_call
    sleep(1.5) # make sure there's nothing pending
    already_flushed = @tracer.writer.stats[:traces_flushed]
    hydra = ::Typhoeus::Hydra.new
    2.times do
      hydra.queue(::Typhoeus::Request.new(ELASTICSEARCH_SERVER))
    end
    hydra.run
    # give hydra time to complete the requests
    sleep(1.5)
    assert_equal(already_flushed + 2, @tracer.writer.stats[:traces_flushed])
  end
end
