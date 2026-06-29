class Context
  protected def remaining_until_deadline : Time::Span?
    @deadline.try { |deadline| deadline - Time.instant }
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

  private def self.effective_deadline(parent_deadline : Time::Instant?, requested_deadline : Time::Instant) : Time::Instant
    return requested_deadline unless parent_deadline

    parent_deadline <= requested_deadline ? parent_deadline : requested_deadline
  end

  # Converts a wall-clock deadline to a monotonic instant so the deadline is
  # unaffected by later system clock adjustments.
  private def self.instant_from_wall(deadline : Time) : Time::Instant
    Time.instant + (deadline - Time.utc)
  end

  protected def schedule_deadline : Nil
    source = @source
    deadline = @deadline
    return unless source && deadline
    return if source.cancelled?

    remaining = deadline - Time.instant
    if remaining <= Time::Span.zero
      source.cancel(DEADLINE_EXCEEDED, by_deadline: true)
      return
    end

    DeadlineScheduler::INSTANCE.register(deadline, source)

    # Closes the race where the parent cancels between the check above and the
    # registration: that cancel's own removal ran before the entry existed, so
    # remove it here once it is in the heap.
    DeadlineScheduler::INSTANCE.remove(source) if source.cancelled?
  end

  private def expire_deadline : Nil
    source = @source
    deadline = @deadline
    return unless source && deadline

    source.cancel(DEADLINE_EXCEEDED, by_deadline: true) if Time.instant >= deadline
  end

  protected def cancel_due_to_deadline! : NoReturn
    @source.try &.cancel(DEADLINE_EXCEEDED, by_deadline: true)
    raise_cancelled!
  end
end
