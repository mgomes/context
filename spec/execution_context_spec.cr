{% if flag?(:execution_context) %}
  require "./spec_helper"

  describe "execution context integration" do
    it "spawns work into an explicit execution context with context cancellation" do
      parent = Context.with_cancel
      default_context = Fiber::ExecutionContext.default
      observed_context = Channel(Bool).new
      stopped = Channel(String).new

      isolated = Fiber::ExecutionContext::Isolated.new("context-spec") do
        Context.spawn(parent, execution_context: default_context) do |child|
          observed_context.send(Fiber::ExecutionContext.current == default_context)
          Context.sleep(child, 1.second)
          stopped.send("completed")
        rescue ex : Context::Cancelled
          stopped.send(ex.message || "")
        end
      end

      isolated.wait
      execution_context_receive_or_fail(
        observed_context,
        "spawned worker did not report its execution context",
      ).should be_true

      parent.cancel("parent stopped")

      execution_context_receive_or_fail(
        stopped,
        "spawned worker did not observe cancellation",
      ).should eq("parent stopped")
    end
  end

  private def execution_context_receive_or_fail(channel : Channel(T), failure : String) : T forall T
    select
    when value = channel.receive
      value
    when timeout(500.milliseconds)
      fail failure
    end
  end
{% end %}
