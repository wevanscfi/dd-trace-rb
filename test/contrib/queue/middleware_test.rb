require 'pry'
require 'timecop'
require 'rack/test'
require 'contrib/queue/helpers'

# rubocop:disable Metrics/ClassLength
class QueueTracerTest < RackQueueBaseTest
  include Rack::Test::Methods

  def test_request_middleware_get
    # ensure the queue start time is poperly set
    # and the durration is what we expect
    ::Timecop.freeze do
      queued_time = Time.now.utc - 10
      header 'X_Request_Start', queued_time.strftime('t=%s.%L')
      get '/success/'
      assert last_response.ok?

      spans = @tracer.writer.spans()
      span = spans[0]
      assert_equal(1, spans.length)

      assert_equal(queued_time.to_i, span.start_time.to_i)
      assert_equal((span.end_time - span.start_time).to_i, 10)
      assert_equal('request.queue', span.name)
      assert_equal('http', span.span_type)
      assert_equal('request_queue', span.service)
      assert_equal('Request Queue', span.resource)
      assert_equal(0, span.status)
      assert_nil(span.parent)
    end
  end
end
