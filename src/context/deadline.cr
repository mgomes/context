class Context
  protected def remaining_until_deadline : Time::Span?
    @deadline.try { |deadline| deadline - Time.utc }
  end

  protected def remaining_until_deadline! : Time::Span?
    remaining = remaining_until_deadline
    return nil unless remaining
    cancel_due_to_deadline! if remaining <= Time::Span.zero

    remaining
  end

  protected def duration_limited_by_deadline!(duration : Time::Span) : Tuple(Time::Span, Bool)
    remaining = remaining_until_deadline!
    return {duration, false} unless remaining
    return {remaining, true} if remaining <= duration

    {duration, false}
  end

  private def self.effective_deadline(parent_deadline : Time?, requested_deadline : Time) : Time
    return requested_deadline unless parent_deadline

    parent_deadline <= requested_deadline ? parent_deadline : requested_deadline
  end

  protected def start_deadline_timer : Nil
    source = @source
    deadline = @deadline
    return unless source && deadline

    remaining = deadline - Time.utc
    if remaining <= Time::Span.zero
      source.cancel(DEADLINE_EXCEEDED)
      return
    end

    spawn do
      select
      when timeout(remaining)
        source.cancel(DEADLINE_EXCEEDED)
      when source.done.receive?
      end
    end
  end

  private def expire_deadline : Nil
    source = @source
    deadline = @deadline
    return unless source && deadline

    source.cancel(DEADLINE_EXCEEDED) if Time.utc >= deadline
  end

  protected def cancel_due_to_deadline! : NoReturn
    cancel(DEADLINE_EXCEEDED)
    raise_cancelled!
  end
end
