class Context
  # Sleeps until `duration` elapses or `ctx` is canceled.
  def self.sleep(ctx : Context, duration : Time::Span) : Nil
    ctx.checkpoint!
    return if duration <= Time::Span.zero

    limited_by_deadline = false
    if remaining = ctx.remaining_until_deadline
      if remaining <= Time::Span.zero
        ctx.cancel(DEADLINE_EXCEEDED)
        raise Cancelled.new(ctx.reason)
      end

      if remaining <= duration
        duration = remaining
        limited_by_deadline = true
      end
    end

    select
    when timeout(duration)
      if limited_by_deadline
        ctx.cancel(DEADLINE_EXCEEDED)
        raise Cancelled.new(ctx.reason)
      end

      ctx.checkpoint!
    when ctx.done.receive?
      ctx.checkpoint!
      raise Cancelled.new(ctx.reason)
    end
  end

  # Receives from `channel` or raises when `ctx` is canceled.
  def self.receive(ctx : Context, channel : Channel(T)) : T forall T
    ctx.checkpoint!

    if remaining = ctx.remaining_until_deadline
      if remaining <= Time::Span.zero
        ctx.cancel(DEADLINE_EXCEEDED)
        raise Cancelled.new(ctx.reason)
      end

      select
      when value = channel.receive
        value
      when ctx.done.receive?
        ctx.checkpoint!
        raise Cancelled.new(ctx.reason)
      when timeout(remaining)
        ctx.cancel(DEADLINE_EXCEEDED)
        raise Cancelled.new(ctx.reason)
      end
    else
      select
      when value = channel.receive
        value
      when ctx.done.receive?
        ctx.checkpoint!
        raise Cancelled.new(ctx.reason)
      end
    end
  end
end
