class Context
  @source : CancelSource?
  @deadline : Time::Instant?
  @values : Hash(ValueKey, ValueBox)

  protected def initialize(
    @source : CancelSource?,
    @deadline : Time::Instant? = nil,
    @values = {} of ValueKey => ValueBox,
  )
  end

  # Returns a root context that is never canceled and has no deadline.
  def self.background : Context
    new(nil)
  end

  # Creates a cancelable context with `Context.background` as its parent.
  def self.with_cancel : Context
    with_cancel(background)
  end

  # Creates a cancelable child context.
  def self.with_cancel(parent : Context) : Context
    new(CancelSource.new(parent.source), parent.deadline, parent.values)
  end

  # Creates a context canceled after `timeout` with `Context.background` as parent.
  def self.with_timeout(timeout : Time::Span) : Context
    with_timeout(background, timeout)
  end

  # Creates a child context canceled when `timeout` expires or its parent is canceled.
  def self.with_timeout(parent : Context, timeout : Time::Span) : Context
    with_deadline_at(parent, Time.instant + timeout)
  end

  # Creates a context canceled at `deadline` with `Context.background` as parent.
  def self.with_deadline(deadline : Time) : Context
    with_deadline(background, deadline)
  end

  # Creates a child context canceled when `deadline` arrives or its parent is canceled.
  def self.with_deadline(parent : Context, deadline : Time) : Context
    with_deadline_at(parent, instant_from_wall(deadline))
  end

  private def self.with_deadline_at(parent : Context, deadline : Time::Instant) : Context
    effective_deadline = effective_deadline(parent.deadline, deadline)
    ctx = new(CancelSource.new(parent.source), effective_deadline, parent.values)
    ctx.start_deadline_timer
    ctx
  end

  # Cancels this context and its children once.
  def cancel(reason : String? = nil) : Bool
    source = @source
    return false unless source

    source.cancel(reason)
  end

  # Returns true when this context has been canceled or its deadline expired.
  def cancelled? : Bool
    expire_deadline
    @source.try(&.cancelled?) || false
  end

  # Returns the effective deadline for this context as a monotonic instant, if any.
  def deadline : Time::Instant?
    @deadline
  end

  # Returns the reason supplied when this context was first canceled.
  def reason : String?
    cancelled?
    @source.try &.reason
  end

  # Raises `Context::Cancelled` if this context is canceled.
  def checkpoint! : Nil
    raise_cancelled! if cancelled?
  end

  protected def source : CancelSource?
    @source
  end

  # Returns a channel that is closed when this context is canceled.
  #
  # Use it to compose your own `select`. Receive-only: never send to or close
  # the returned channel. A context with no cancellation source returns a fresh
  # channel that never closes.
  def done : Channel(Nil)
    @source.try(&.done) || Channel(Nil).new
  end

  protected def raise_cancelled! : NoReturn
    current_reason = reason
    if @source.try(&.by_deadline?)
      raise DeadlineExceeded.new(current_reason)
    else
      raise Cancelled.new(current_reason)
    end
  end

  protected def values : Hash(ValueKey, ValueBox)
    @values
  end
end
