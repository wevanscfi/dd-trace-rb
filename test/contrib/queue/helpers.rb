require 'helper'
require 'ddtrace'
require 'rack/test'
require 'ddtrace/contrib/queue/middlewares'

class RackQueueBaseTest < Minitest::Test
  include Rack::Test::Methods

  # rubocop:disable Metrics/MethodLength
  def app
    tracer = @tracer

    Rack::Builder.new do
      use Datadog::Contrib::Queue::TraceMiddleware, tracer: tracer

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
