require "./spec_helper"

# Stress the cancellation and deadline primitives under concurrency. The racing
# fibers are spawned with `stress_spawn`: under `-Dexecution_context` they run in
# a dedicated parallel context so they execute across real OS threads (the
# default context runs at parallelism 1, which would keep them cooperative);
# otherwise they fall back to plain `spawn`.
#
# Each test uses a broadcast barrier: every worker reports that it is parked on a
# shared `gate`, and once all are parked the gate is closed, releasing them at
# once (a per-worker `send` would release them one at a time and serialize the
# race). The asserted invariant must hold regardless of scheduling.
{% if flag?(:execution_context) %}
  CONCURRENCY_STRESS_CONTEXT = Fiber::ExecutionContext::Parallel.new("concurrency-stress", 4)

  private def stress_spawn(&block : ->)
    CONCURRENCY_STRESS_CONTEXT.spawn(&block)
  end
{% else %}
  private def stress_spawn(&block : ->)
    spawn(&block)
  end
{% end %}

describe "concurrency" do
  it "has exactly one winner when many fibers cancel one context at once" do
    50.times do
      ctx = Context.with_cancel
      ready = Channel(Nil).new
      gate = Channel(Nil).new
      results = Channel(Bool).new
      reasons = (0...16).map { |i| "reason-#{i}" }

      reasons.each do |reason|
        stress_spawn do
          ready.send(nil)
          gate.receive?
          results.send(ctx.cancel(reason))
        end
      end

      reasons.size.times { ready.receive }
      gate.close

      wins = 0
      reasons.size.times { wins += 1 if results.receive }

      wins.should eq(1)
      reasons.should contain(ctx.reason)
    end
  end

  it "cancels every child created concurrently with the parent's cancellation" do
    parent = Context.with_cancel
    ready = Channel(Nil).new
    gate = Channel(Nil).new
    children = Channel(Context).new
    cancel_done = Channel(Nil).new
    count = 100

    count.times do
      stress_spawn do
        ready.send(nil)
        gate.receive?
        children.send(Context.with_cancel(parent))
      end
    end

    stress_spawn do
      ready.send(nil)
      gate.receive?
      parent.cancel("shutdown")
      cancel_done.send(nil)
    end

    (count + 1).times { ready.receive }
    gate.close

    collected = Array.new(count) { children.receive }
    cancel_done.receive

    collected.all?(&.cancelled?).should be_true
    collected.each { |child| child.reason.should eq("shutdown") }
  end

  it "stays consistent while many timeout contexts register and cancel at once" do
    ready = Channel(Nil).new
    gate = Channel(Nil).new
    done = Channel(Nil).new
    count = 200

    count.times do
      stress_spawn do
        ready.send(nil)
        gate.receive?
        ctx = Context.with_timeout(1.hour)
        ctx.cancel("done")
        done.send(nil)
      end
    end

    count.times { ready.receive }
    gate.close
    count.times { done.receive }

    canary = Context.with_timeout(20.milliseconds)
    woke = Channel(Nil).new
    stress_spawn do
      canary.done.receive?
      woke.send(nil)
    end

    select
    when woke.receive
    when timeout(500.milliseconds)
      fail "scheduler stalled under concurrent register/cancel"
    end
  end

  it "wakes every fiber blocked on a shared parent when it is canceled" do
    parent = Context.with_cancel
    ready = Channel(Nil).new
    stopped = Channel(String).new
    count = 100

    count.times do
      stress_spawn do
        child = Context.with_cancel(parent)
        ready.send(nil)
        begin
          Context.sleep(child, 1.second)
          stopped.send("completed")
        rescue ex : Context::Cancelled
          stopped.send(ex.message || "")
        end
      end
    end

    count.times { ready.receive }
    parent.cancel("halt")

    results = Array.new(count) { stopped.receive }
    results.all?("halt").should be_true
  end
end
