require "./spec_helper"

describe "deadline scheduler" do
  it "wakes a done waiter for the earliest deadline even when it registers last" do
    later = Context.with_timeout(300.milliseconds)
    sooner = Context.with_timeout(20.milliseconds)
    woke = Channel(Nil).new

    spawn do
      sooner.done.receive?
      woke.send(nil)
    end

    select
    when woke.receive
    when timeout(200.milliseconds)
      fail "scheduler did not fire the earliest deadline in time"
    end

    later.cancelled?.should be_false
  end

  it "fires many deadlines from one shared scheduler" do
    contexts = Array.new(100) { Context.with_timeout(20.milliseconds) }

    Context.sleep(Context.background, 80.milliseconds)

    contexts.all?(&.cancelled?).should be_true
    contexts.each { |ctx| ctx.reason.should eq(Context::DEADLINE_EXCEEDED) }
  end

  it "closes an extracted done channel at the deadline even if the context is dropped" do
    done = Context.with_timeout(30.milliseconds).done
    GC.collect

    woke = Channel(Nil).new
    spawn do
      done.receive?
      woke.send(nil)
    end

    select
    when woke.receive
    when timeout(500.milliseconds)
      fail "extracted done channel never closed after the context was dropped"
    end
  end

  it "keeps firing later deadlines after an earlier context is canceled manually" do
    early = Context.with_timeout(20.milliseconds)
    later = Context.with_timeout(60.milliseconds)
    woke = Channel(Nil).new

    early.cancel("manual stop")

    spawn do
      later.done.receive?
      woke.send(nil)
    end

    select
    when woke.receive
    when timeout(300.milliseconds)
      fail "scheduler stalled after an earlier manual cancel"
    end

    early.reason.should eq("manual stop")
  end

  it "drains canceled long-timeout contexts and still fires fresh ones" do
    canceled = Array.new(50) { Context.with_timeout(1.hour) }
    canceled.each(&.cancel("done"))

    short = Context.with_timeout(20.milliseconds)
    woke = Channel(Nil).new

    spawn do
      short.done.receive?
      woke.send(nil)
    end

    select
    when woke.receive
    when timeout(500.milliseconds)
      fail "scheduler broke after canceling many long-timeout contexts"
    end
  end
end
