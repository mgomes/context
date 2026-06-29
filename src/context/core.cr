class Context
  @@never_done = Channel(Nil).new

  @source : CancelSource?
  @deadline : Time?

  private def initialize(@source : CancelSource?, @deadline : Time? = nil)
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
    new(CancelSource.new(parent.source), parent.deadline)
  end

  # Creates a context canceled after `timeout` with `Context.background` as parent.
  def self.with_timeout(timeout : Time::Span) : Context
    with_timeout(background, timeout)
  end

  # Creates a child context canceled when `timeout` expires or its parent is canceled.
  def self.with_timeout(parent : Context, timeout : Time::Span) : Context
    requested_deadline = Time.utc + timeout
    ctx = new(CancelSource.new(parent.source), effective_deadline(parent.deadline, requested_deadline))
    ctx.start_deadline_timer
    ctx.cancel(DEADLINE_EXCEEDED) if timeout <= Time::Span.zero
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

  # Returns the effective deadline for this context, if any.
  def deadline : Time?
    @deadline
  end

  # Returns the reason supplied when this context was first canceled.
  def reason : String?
    cancelled?
    @source.try &.reason
  end

  # Raises `Context::Cancelled` if this context is canceled.
  def checkpoint! : Nil
    raise Cancelled.new(reason) if cancelled?
  end

  protected def source : CancelSource?
    @source
  end

  protected def done : Channel(Nil)
    @source.try(&.done) || @@never_done
  end
end
