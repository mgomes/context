require "weak_ref"

# Go-style cooperative cancellation, deadlines, and blocking helpers for Crystal.
class Context
  DEFAULT_REASON    = "context cancelled"
  DEADLINE_EXCEEDED = "context deadline exceeded"

  @@never_done = Channel(Nil).new

  # Raised by `Context#checkpoint!` and context-aware blocking helpers.
  class Cancelled < Exception
    # Creates a cancellation exception with a stable default message.
    def initialize(reason : String? = nil)
      super(reason || DEFAULT_REASON)
    end
  end

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

  protected def remaining_until_deadline : Time::Span?
    @deadline.try { |deadline| deadline - Time.utc }
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

  private class CancelSource
    getter done

    @parent : CancelSource?
    @children : Array(WeakRef(CancelSource))
    @cancelled : Bool
    @reason : String?

    def initialize(@parent : CancelSource? = nil)
      @done = Channel(Nil).new
      @mutex = Mutex.new
      @children = [] of WeakRef(CancelSource)
      @cancelled = false
      @reason = nil
      @parent.try &.add_child(self)
    end

    def cancel(reason : String? = nil) : Bool
      children = [] of CancelSource
      parent = nil.as(CancelSource?)

      @mutex.synchronize do
        return false if @cancelled

        @cancelled = true
        @reason = reason
        @children.each do |child_ref|
          if child = child_ref.value
            children << child
          end
        end
        @children.clear
        parent = @parent
        @parent = nil
        @done.close
      end

      parent.try &.remove_child(self)
      children.each { |child| child.cancel(reason) }
      true
    end

    def cancelled? : Bool
      @mutex.synchronize { @cancelled }
    end

    def reason : String?
      @mutex.synchronize { @reason }
    end

    protected def add_child(child : CancelSource) : Nil
      cancel_child = false
      reason = nil.as(String?)

      @mutex.synchronize do
        if @cancelled
          cancel_child = true
          reason = @reason
        else
          prune_dead_children
          @children << WeakRef.new(child)
        end
      end

      child.cancel(reason) if cancel_child
    end

    protected def remove_child(child : CancelSource) : Nil
      @mutex.synchronize do
        unless @cancelled
          @children.reject! do |child_ref|
            current_child = child_ref.value
            current_child.nil? || current_child == child
          end
        end
      end
    end

    private def prune_dead_children : Nil
      @children.reject! { |child_ref| child_ref.value.nil? }
    end
  end
end
