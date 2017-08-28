require 'contrib/sidekiq/tracer_test_base'

class QueueTracerTest < TracerTestBase
  class TestError < StandardError; end

  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  def test_queue
    job = {
      'class' => 'TracerTest::EmptyWorker',
      'queue' => 'default',
      'jid' => '1234543',
      'retry' => false,
      'enqueued_at' => (Time.now.utc - 10).strftime('%s.%L')
    }

    Datadog::Contrib::Sidekiq::Tracer.new(tracer: @tracer, enabled: true).call(
      EmptyWorker,
      job,
      'default'
    ) {}

    spans = @writer.spans()
    assert_equal(2, spans.length)

    # The queue span
    span = spans[0]
    assert_equal('sidekiq', span.service)
    assert_equal('default', span.get_tag('sidekiq.queue.queue'))
    assert_equal('queue', span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)

    # The job span
    span = spans[1]
    assert_equal('sidekiq', span.service)
    assert_equal('TracerTest::EmptyWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    assert_equal('job', span.span_type)
    assert_equal(0, span.status)
    assert_nil(span.parent)

  end
end
