require 'helper'
require 'ddtrace'
require 'rack/test'
require 'ddtrace/contrib/preprocess/middlewares'

class RackQueueBaseTest < Minitest::Test
  include Rack::Test::Methods

  # rubocop:disable Metrics/MethodLength
  def app
    tracer = @tracer

    Rack::Builder.new do
      # Example Preprocess Use
      # Trace time since the request was
      # queued by uicorn
      use Datadog::Contrib::Preprocess::TimingHeaderMiddleware, {
        service: 'unicorn',
        name: 'request.queue',
        tracer: tracer
      }

      # Example Preprocess Use
      # Trace time since the request was
      # routed at the edge routing servers
      # until it was placed in unicorn queue
      use Datadog::Contrib::Preprocess::TimingHeaderMiddleware, {
        service: 'edgerouter',
        name: 'routing.latency',
        timing_start_header: 'HTTP_X_EDGE_ROUTE_START',
        timing_end_header: 'HTTP_X_REQUEST_START',
        app: 'edge-router',
        tracer: tracer
      }

      map '/success/' do
        run(proc { |_env| [200, { 'Content-Type' => 'text/html' }, 'OK'] })
      end
    end.to_app
  end

  def setup
    # configure our Middleware with a DummyTracer
    @tracer = get_test_tracer()
    super
  end
end
