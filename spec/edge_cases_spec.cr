require "./spec_helper"

describe "context edge cases" do
  it "cancels zero and negative timeouts immediately" do
    [Time::Span.zero, -1.millisecond].each do |timeout|
      ctx = Context.with_timeout(timeout)

      ctx.cancelled?.should be_true
      ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
      expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) { ctx.checkpoint! }
    end
  end

  it "cancels past deadlines immediately" do
    ctx = Context.with_deadline(Time.utc - 1.millisecond)

    ctx.cancelled?.should be_true
    ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "cancels future deadlines after they expire" do
    ctx = Context.with_deadline(Time.utc + 10.milliseconds)

    Context.sleep(Context.background, 30.milliseconds)

    ctx.cancelled?.should be_true
    ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "uses the child deadline when it is earlier than the parent deadline" do
    parent = Context.with_timeout(1.second)
    child = Context.with_timeout(parent, 10.milliseconds)

    Context.sleep(Context.background, 30.milliseconds)

    parent.cancelled?.should be_false
    child.cancelled?.should be_true
    child.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "uses the parent deadline when it is earlier than the child deadline" do
    parent = Context.with_timeout(10.milliseconds)
    child = Context.with_timeout(parent, 1.second)

    Context.sleep(Context.background, 30.milliseconds)

    parent.cancelled?.should be_true
    child.cancelled?.should be_true
    child.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "preserves a manual cancellation reason after the deadline timer fires" do
    ctx = Context.with_timeout(10.milliseconds)

    ctx.cancel("manual stop").should be_true
    Context.sleep(Context.background, 30.milliseconds)

    ctx.cancelled?.should be_true
    ctx.reason.should eq("manual stop")
  end

  it "preserves the deadline reason after a later manual cancellation" do
    ctx = Context.with_timeout(10.milliseconds)

    Context.sleep(Context.background, 30.milliseconds)

    ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
    ctx.cancel("manual stop").should be_false
    ctx.reason.should eq(Context::DEADLINE_EXCEEDED)
  end

  it "allows only one concurrent cancellation winner" do
    ctx = Context.with_cancel
    start = Channel(Nil).new
    results = Channel(Tuple(String, Bool)).new
    reasons = (0...10).map { |index| "reason #{index}" }

    reasons.each do |reason|
      spawn do
        start.receive
        results.send({reason, ctx.cancel(reason)})
      end
    end

    reasons.size.times { start.send(nil) }
    attempts = reasons.map { results.receive }
    winners = attempts.select { |_, won| won }

    winners.size.should eq(1)
    reasons.should contain(ctx.reason)
    ctx.reason.should eq(winners.first[0])
  end

  it "does not let child cancellation cancel siblings or parents" do
    parent = Context.with_cancel
    first_child = Context.with_cancel(parent)
    second_child = Context.with_cancel(parent)

    first_child.cancel("first stopped").should be_true

    parent.cancelled?.should be_false
    second_child.cancelled?.should be_false
    first_child.reason.should eq("first stopped")
  end

  it "does not overwrite a detached child reason when the parent is later canceled" do
    parent = Context.with_cancel
    child = Context.with_cancel(parent)

    child.cancel("child done").should be_true
    parent.cancel("parent stopped").should be_true

    child.reason.should eq("child done")
  end

  it "cancels many child contexts from one parent" do
    parent = Context.with_cancel
    children = Array.new(50) { Context.with_cancel(parent) }

    parent.cancel("fanout").should be_true

    children.each do |child|
      child.cancelled?.should be_true
      child.reason.should eq("fanout")
    end
  end

  it "raises channel closure from receive when the context is active" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new
    channel.close

    expect_raises(Channel::ClosedError) do
      Context.receive(ctx, channel)
    end
  end

  it "raises cancellation before receiving an already buffered value" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new(1)

    channel.send(42)
    ctx.cancel("do not consume")

    expect_raises(Context::Cancelled, "do not consume") do
      Context.receive(ctx, channel)
    end

    channel.receive.should eq(42)
  end

  it "sends channel values before cancellation" do
    ctx = Context.with_cancel
    channel = Channel(String).new
    sent = Channel(String).new

    spawn do
      Context.send(ctx, channel, "hello")
      sent.send("sent")
    rescue ex
      sent.send("#{ex.class}: #{ex.message}")
    end

    channel.receive.should eq("hello")
    edge_receive_or_fail(sent, "send did not complete").should eq("sent")
  end

  it "wakes send when canceled" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new
    result = Channel(String).new

    spawn do
      Context.send(ctx, channel, 1)
      result.send("sent")
    rescue ex : Context::Cancelled
      result.send(ex.message || "")
    end

    Context.sleep(Context.background, 10.milliseconds)
    ctx.cancel("send canceled")

    edge_receive_or_fail(result, "send did not wake after cancellation").should eq("send canceled")
  end

  it "wakes send when its deadline expires" do
    ctx = Context.with_timeout(10.milliseconds)
    channel = Channel(Int32).new

    expect_raises(Context::Cancelled, Context::DEADLINE_EXCEEDED) do
      Context.send(ctx, channel, 1)
    end
  end

  it "raises channel closure from send when the context is active" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new
    channel.close

    expect_raises(Channel::ClosedError) do
      Context.send(ctx, channel, 1)
    end
  end

  it "raises cancellation before sending into an available buffer" do
    ctx = Context.with_cancel
    channel = Channel(Int32).new(1)

    ctx.cancel("do not send")

    expect_raises(Context::Cancelled, "do not send") do
      Context.send(ctx, channel, 1)
    end

    select
    when channel.receive
      fail "send should not have written to the channel"
    when timeout(10.milliseconds)
    end
  end

  it "stores and retrieves symbol-keyed values with explicit types" do
    ctx = Context.background.with_value(:sandbox_id, "sandbox-1")

    ctx.value(:sandbox_id, String).should eq("sandbox-1")
    ctx.value(:sandbox_id, Int32).should be_nil
    Context.background.value(:sandbox_id, String).should be_nil
  end

  it "stores and retrieves typed key values across child contexts" do
    request_id = Context::Key(String).new(:request_id)
    parent = Context.background.with_value(request_id, "req-123")
    child = Context.with_cancel(parent)

    child.value(request_id).should eq("req-123")
    child.with_value(request_id, "req-456").value(request_id).should eq("req-456")
    parent.value(request_id).should eq("req-123")
  end

  it "spawns work with a child context tied to the parent" do
    parent = Context.with_cancel
    ready = Channel(Nil).new
    stopped = Channel(String).new

    Context.spawn(parent) do |child|
      ready.send(nil)
      Context.sleep(child, 1.second)
      stopped.send("completed")
    rescue ex : Context::Cancelled
      stopped.send(ex.message || "")
    end

    ready.receive
    parent.cancel("parent stopped")

    edge_receive_or_fail(stopped, "spawned worker did not stop").should eq("parent stopped")
  end

  it "does not cancel the parent when spawned work completes" do
    parent = Context.with_cancel
    done = Channel(Nil).new

    Context.spawn(parent) do |child|
      child.checkpoint!
      done.send(nil)
    end

    edge_receive_or_fail(done, "spawned worker did not complete")
    parent.cancelled?.should be_false
  end
end

private def edge_receive_or_fail(channel : Channel(T), failure : String) : T forall T
  select
  when value = channel.receive
    value
  when timeout(500.milliseconds)
    fail failure
  end
end
