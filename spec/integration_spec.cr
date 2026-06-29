require "./spec_helper"

module IntegrationSpec
  class Inbox
    getter ready

    def initialize
      @messages = Channel(String).new
      @ready = Channel(Nil).new
    end

    def send(message : String) : Nil
      @messages.send(message)
    end

    def read(ctx : Context) : String
      @ready.send(nil)
      Context.receive(ctx, @messages)
    end
  end

  class Repository
    def initialize(@inbox : Inbox)
    end

    def next_message(ctx : Context) : String
      message = @inbox.read(ctx)
      Context.sleep(ctx, 1.millisecond)
      "repo:#{message}"
    end
  end

  class Service
    def initialize(@repository : Repository)
    end

    def handle(ctx : Context, timeout : Time::Span) : String
      request_ctx = Context.with_timeout(ctx, timeout)
      "service:#{@repository.next_message(request_ctx)}"
    end
  end

  class DeadlineStack
    def call(ctx : Context, timeout : Time::Span) : String
      child_ctx = Context.with_timeout(ctx, timeout)
      fetch(child_ctx)
    end

    private def fetch(ctx : Context) : String
      decode(ctx)
    end

    private def decode(ctx : Context) : String
      Context.sleep(ctx, 1.second)
      "decoded"
    end
  end

  class CooperativeSandbox
    getter instructions_executed

    def initialize
      @instructions_executed = 0
    end

    def run(ctx : Context) : Nil
      prepare(ctx)
      execute(ctx)
    end

    private def prepare(ctx : Context) : Nil
      Context.sleep(ctx, 1.millisecond)
    end

    private def execute(ctx : Context) : Nil
      loop do
        ctx.checkpoint!
        @instructions_executed += 1
      end
    end
  end

  class FiniteSandbox
    getter instructions_executed

    def initialize
      @instructions_executed = 0
    end

    def run(ctx : Context, instruction_count : Int32) : Nil
      instruction_count.times do
        ctx.checkpoint!
        @instructions_executed += 1
      end
    end
  end
end

describe "context integration" do
  it "passes a context through a service stack and completes before timeout" do
    inbox = IntegrationSpec::Inbox.new
    service = IntegrationSpec::Service.new(IntegrationSpec::Repository.new(inbox))
    result = Channel(String).new

    spawn do
      result.send(service.handle(Context.background, 1.second))
    rescue ex : Context::Cancelled
      result.send("cancelled: #{ex.message}")
    end

    receive_or_fail(inbox.ready, "service did not block on inbox")
    inbox.send("hello")

    receive_or_fail(result, "service did not complete").should eq("service:repo:hello")
  end

  it "propagates parent cancellation through a child timeout context while blocked" do
    parent = Context.with_cancel
    inbox = IntegrationSpec::Inbox.new
    service = IntegrationSpec::Service.new(IntegrationSpec::Repository.new(inbox))
    result = Channel(String).new

    spawn do
      result.send(service.handle(parent, 1.second))
    rescue ex : Context::Cancelled
      result.send("cancelled: #{ex.message}")
    end

    receive_or_fail(inbox.ready, "service did not block on inbox")
    parent.cancel("client aborted")

    receive_or_fail(result, "service did not observe cancellation").should eq("cancelled: client aborted")
  end

  it "honors the earliest deadline across nested child contexts" do
    parent = Context.with_timeout(20.milliseconds)
    stack = IntegrationSpec::DeadlineStack.new
    started_at = Time.instant

    expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) do
      stack.call(parent, 1.second)
    end

    (Time.instant - started_at).should be < 500.milliseconds
    parent.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "cancels multiple child workers blocked below one parent context" do
    parent = Context.with_cancel
    jobs = Channel(Int32).new
    ready = Channel(Int32).new
    stopped = Channel(String).new

    2.times do |index|
      spawn do
        child = Context.with_cancel(parent)
        ready.send(index)

        begin
          Context.receive(child, jobs)
        rescue ex : Context::Cancelled
          stopped.send("worker #{index}: #{ex.message}")
        end
      end
    end

    2.times { receive_or_fail(ready, "worker did not start") }
    parent.cancel("deploy")

    messages = [
      receive_or_fail(stopped, "first worker did not stop"),
      receive_or_fail(stopped, "second worker did not stop"),
    ].sort

    messages.should eq(["worker 0: deploy", "worker 1: deploy"])
  end

  it "stops a cooperative sandbox through nested runtime checkpoints" do
    sandbox = IntegrationSpec::CooperativeSandbox.new
    ctx = Context.with_timeout(10.milliseconds)

    expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) do
      sandbox.run(ctx)
    end

    sandbox.instructions_executed.should be > 0
    ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "lets finite cooperative sandbox work complete normally" do
    sandbox = IntegrationSpec::FiniteSandbox.new
    ctx = Context.with_timeout(1.second)

    sandbox.run(ctx, 100)

    sandbox.instructions_executed.should eq(100)
    ctx.cancelled?.should be_false
  end

  it "carries typed values through timeout and spawn boundaries" do
    request_id = Context::Key(String).new(:request_id)
    parent = Context.background
      .with_value(:sandbox_id, "sandbox-7")
      .with_value(request_id, "req-9")
    timed = Context.with_timeout(parent, 1.second)
    observed = Channel(String).new

    Context.spawn(timed) do |ctx|
      sandbox_id = ctx.value(:sandbox_id, String).not_nil!
      request = ctx.value(request_id).not_nil!
      observed.send("#{sandbox_id}:#{request}")
    end

    receive_or_fail(observed, "spawned worker did not observe values").should eq("sandbox-7:req-9")
  end
end

private def receive_or_fail(channel : Channel(T), failure : String) : T forall T
  select
  when value = channel.receive
    value
  when timeout(500.milliseconds)
    fail failure
  end
end
