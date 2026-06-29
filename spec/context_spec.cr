require "./spec_helper"

describe Context do
  it "provides a background context that is never canceled" do
    ctx = Context.background

    ctx.cancelled?.should be_false
    ctx.reason.should be_nil
    ctx.cancel.should be_false
    ctx.checkpoint!
  end

  it "cancels explicitly and preserves the first reason" do
    ctx = Context.with_cancel

    ctx.cancel("stop").should be_true
    ctx.cancelled?.should be_true
    ctx.reason.should eq("stop")

    ctx.cancel("later").should be_false
    ctx.reason.should eq("stop")
  end

  it "propagates parent cancellation to children synchronously" do
    parent = Context.with_cancel
    child = Context.with_cancel(parent)

    parent.cancel("parent stopped").should be_true

    child.cancelled?.should be_true
    child.reason.should eq("parent stopped")
  end

  it "cancels children created after parent cancellation" do
    parent = Context.with_cancel

    parent.cancel("already stopped").should be_true
    child = Context.with_cancel(parent)

    child.cancelled?.should be_true
    child.reason.should eq("already stopped")
  end

  it "cancels descendants when an intermediate child is canceled" do
    parent = Context.with_cancel
    child = Context.with_cancel(parent)
    grandchild = Context.with_cancel(child)

    child.cancel("child stopped").should be_true

    parent.cancelled?.should be_false
    grandchild.cancelled?.should be_true
    grandchild.reason.should eq("child stopped")
  end

  it "cancels after a timeout" do
    ctx = Context.with_timeout(10.milliseconds)

    ::sleep 30.milliseconds

    ctx.cancelled?.should be_true
    ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "exposes the deadline as a monotonic instant" do
    ctx = Context.with_timeout(1.second)

    deadline = ctx.deadline
    deadline.should be_a(Time::Instant)
    remaining = deadline.not_nil! - Time.instant
    remaining.should be > Time::Span.zero
    remaining.should be <= 1.second
  end

  it "propagates timeout cancellation to children" do
    parent = Context.with_timeout(10.milliseconds)
    child = Context.with_cancel(parent)

    ::sleep 30.milliseconds

    parent.cancelled?.should be_true
    child.cancelled?.should be_true
    child.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "makes checkpoint observe deadline expiration without a scheduler yield" do
    ctx = Context.with_timeout(5.milliseconds)

    expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) do
      loop do
        ctx.checkpoint!
      end
    end
  end

  it "raises the cancellation reason from checkpoint" do
    ctx = Context.with_cancel

    ctx.cancel("boom")

    expect_raises(Context::Cancelled, "boom") do
      ctx.checkpoint!
    end
  end

  it "raises Context::DeadlineExceeded when a deadline expires" do
    ctx = Context.with_timeout(5.milliseconds)

    expect_raises(Context::DeadlineExceeded, Context::DEADLINE_EXCEEDED) do
      loop { ctx.checkpoint! }
    end
  end

  it "raises base Context::Cancelled, not DeadlineExceeded, on manual cancellation" do
    ctx = Context.with_cancel
    ctx.cancel("boom")

    error = expect_raises(Context::Cancelled, "boom") { ctx.checkpoint! }
    error.should_not be_a(Context::DeadlineExceeded)
  end

  it "treats a manual cancel as Cancelled even when given the deadline message" do
    ctx = Context.with_cancel
    ctx.cancel(Context::DEADLINE_EXCEEDED)

    error = expect_raises(Context::Cancelled) { ctx.checkpoint! }
    error.should_not be_a(Context::DeadlineExceeded)
  end

  it "wakes sleep when canceled" do
    ctx = Context.with_cancel
    elapsed = Channel(Time::Span).new
    started_at = Time.instant

    spawn do
      begin
        Context.sleep(ctx, 1.second)
      rescue Context::Cancelled
        elapsed.send(Time.instant - started_at)
      end
    end

    ::sleep 10.milliseconds
    ctx.cancel("wake")

    select
    when duration = elapsed.receive
      duration.should be < 500.milliseconds
    when timeout(500.milliseconds)
      fail "sleep did not wake after cancellation"
    end
  end

  it "raises from sleep when its deadline expires" do
    ctx = Context.with_timeout(10.milliseconds)

    expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) do
      Context.sleep(ctx, 1.second)
    end
  end

  it "receives a channel value before cancellation" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new

    spawn { channel.send(42) }

    Context.receive(ctx, channel).should eq(42)
  end

  it "wakes receive when canceled" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new
    result = Channel(String).new

    spawn do
      begin
        Context.receive(ctx, channel)
        result.send("received")
      rescue ex : Context::Cancelled
        result.send(ex.message || "")
      end
    end

    ::sleep 10.milliseconds
    ctx.cancel("receive canceled")

    select
    when message = result.receive
      message.should eq("receive canceled")
    when timeout(500.milliseconds)
      fail "receive did not wake after cancellation"
    end
  end

  it "wakes receive when its deadline expires" do
    ctx = Context.with_timeout(10.milliseconds)
    channel = Channel(Int32).new

    expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) do
      Context.receive(ctx, channel)
    end
  end

  it "exposes a public done channel for custom selects" do
    ctx = Context.with_cancel
    other = Channel(Int32).new
    result = Channel(String).new

    spawn do
      select
      when other.receive
        result.send("other")
      when ctx.done.receive?
        result.send("done")
      end
    end

    ::sleep 10.milliseconds
    ctx.cancel("stop")

    select
    when message = result.receive
      message.should eq("done")
    when timeout(500.milliseconds)
      fail "custom select did not observe cancellation"
    end
  end

  it "closes the done channel when a deadline expires" do
    ctx = Context.with_timeout(10.milliseconds)
    result = Channel(Nil).new

    spawn do
      ctx.done.receive?
      result.send(nil)
    end

    select
    when result.receive
    when timeout(500.milliseconds)
      fail "done channel did not close at the deadline"
    end
  end

  it "does not share a done channel across sourceless contexts" do
    Context.background.done.same?(Context.background.done).should be_false
  end
end
