require "./spec_helper"

# Stress the cancellation and deadline primitives under concurrency. These run
# in the default scheduler and, in CI, under `-Dpreview_mt -Dexecution_context`
# so the same invariants are exercised across real OS threads. Each test gates
# its fibers on a barrier channel to maximize contention, then asserts a
# structural invariant that must hold regardless of scheduling.
describe "concurrency" do
  it "has exactly one winner when many fibers cancel one context at once" do
    50.times do
      ctx = Context.with_cancel
      start = Channel(Nil).new
      results = Channel(Bool).new
      reasons = (0...16).map { |i| "reason-#{i}" }

      reasons.each do |reason|
        spawn do
          start.receive
          results.send(ctx.cancel(reason))
        end
      end

      reasons.size.times { start.send(nil) }
      wins = 0
      reasons.size.times { wins += 1 if results.receive }

      wins.should eq(1)
      reasons.should contain(ctx.reason)
    end
  end

  it "cancels every child created concurrently with the parent's cancellation" do
    parent = Context.with_cancel
    start = Channel(Nil).new
    children = Channel(Context).new
    cancel_done = Channel(Nil).new
    count = 100

    count.times do
      spawn do
        start.receive
        children.send(Context.with_cancel(parent))
      end
    end

    spawn do
      start.receive
      parent.cancel("shutdown")
      cancel_done.send(nil)
    end

    (count + 1).times { start.send(nil) }

    collected = Array.new(count) { children.receive }
    cancel_done.receive

    collected.all?(&.cancelled?).should be_true
    collected.each { |child| child.reason.should eq("shutdown") }
  end

  it "stays consistent while many timeout contexts register and cancel at once" do
    start = Channel(Nil).new
    done = Channel(Nil).new
    count = 200

    count.times do
      spawn do
        start.receive
        ctx = Context.with_timeout(1.hour)
        ctx.cancel("done")
        done.send(nil)
      end
    end

    count.times { start.send(nil) }
    count.times { done.receive }

    canary = Context.with_timeout(20.milliseconds)
    woke = Channel(Nil).new
    spawn do
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
      spawn do
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
