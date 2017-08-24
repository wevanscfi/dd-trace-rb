require 'pry'
require 'timecop'
require 'rack/test'
require 'contrib/preprocess/helpers'

# rubocop:disable Metrics/ClassLength
class TimingHeaderTest < RackQueueBaseTest
  include Rack::Test::Methods

  def test_request_middleware_get
    # ensure the queue start time is poperly set
    # and the durration is what we expect
    ::Timecop.freeze do
      edge_time = Time.now.utc - 10
      queued_time = Time.now.utc - 2
      header 'X_Request_Start', queued_time.strftime('t=%s.%L')
      header 'X_Edge_Route_Start', edge_time.strftime('t=%s.%L')
      get '/success/'
      assert last_response.ok?

      spans = @tracer.writer.spans()
      assert_equal(2, spans.length)

      span = spans[0]
      assert_equal(queued_time.to_i, span.start_time.to_i)
      assert_equal(2, (span.end_time - span.start_time).to_i)
      assert_equal('upstream', span.span_type)
      assert_equal('unicorn', span.service)
      assert_equal(nil, span.resource)
      assert_equal('request.queue', span.name)
      assert_equal(0, span.status)
      assert_nil(span.parent)

      span = spans[1]
      assert_equal(edge_time.to_i, span.start_time.to_i)
      assert_equal(8, (span.end_time - span.start_time).to_i)
      assert_equal('upstream', span.span_type)
      assert_equal('edgerouter', span.service)
      assert_equal(nil, span.resource)
      assert_equal('routing.latency', span.name)
      assert_equal(0, span.status)
      assert_nil(span.parent)
    end
  end
end
