class Context
  # Sleeps until `duration` elapses or `ctx` is canceled.
  def self.sleep(ctx : Context, duration : Time::Span) : Nil
    ctx.checkpoint!
    return if duration <= Time::Span.zero

    duration, limited_by_deadline = ctx.duration_limited_by_deadline!(duration)

    select
    when timeout(duration)
      if limited_by_deadline
        ctx.cancel_due_to_deadline!
      end

      ctx.checkpoint!
    when ctx.done.receive?
      ctx.raise_cancelled!
    end
  end

  # Receives from `channel` or raises when `ctx` is canceled.
  def self.receive(ctx : Context, channel : Channel(T)) : T forall T
    ctx.checkpoint!

    if remaining = ctx.remaining_until_deadline!
      select
      when value = channel.receive
        value
      when ctx.done.receive?
        ctx.raise_cancelled!
      when timeout(remaining)
        ctx.cancel_due_to_deadline!
      end
    else
      select
      when value = channel.receive
        value
      when ctx.done.receive?
        ctx.raise_cancelled!
      end
    end
  end

  # Sends `value` to `channel` or raises when `ctx` is canceled.
  def self.send(ctx : Context, channel : Channel(T), value : T) : Nil forall T
    ctx.checkpoint!

    if remaining = ctx.remaining_until_deadline!
      select
      when channel.send(value)
      when ctx.done.receive?
        ctx.raise_cancelled!
      when timeout(remaining)
        ctx.cancel_due_to_deadline!
      end
    else
      select
      when channel.send(value)
      when ctx.done.receive?
        ctx.raise_cancelled!
      end
    end
  end
end
