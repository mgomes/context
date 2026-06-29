class Context
  # Fires context deadlines from a single shared background fiber instead of one
  # fiber per deadline.
  #
  # Pending deadlines live in a min-heap keyed by instant. An entry holds its
  # source until the deadline fires, so a caller that keeps only `Context#done`
  # (without retaining the context) still wakes when the deadline expires. The
  # background fiber sleeps until the earliest deadline and is woken early when a
  # sooner one registers.
  private class DeadlineScheduler
    private record Entry, deadline : Time::Instant, source : CancelSource

    def initialize
      @mutex = Mutex.new
      @heap = [] of Entry
      @wakeup = Channel(Nil).new(1)
      @started = false
    end

    # Registers `source` to be canceled at `deadline`.
    def register(deadline : Time::Instant, source : CancelSource) : Nil
      wake = false

      @mutex.synchronize do
        earliest = @heap.first?.try(&.deadline)
        push(Entry.new(deadline, source))
        ensure_started
        wake = earliest.nil? || deadline < earliest
      end

      signal_wakeup if wake
    end

    private def ensure_started : Nil
      return if @started
      @started = true

      {% if flag?(:execution_context) %}
        Fiber::ExecutionContext.default.spawn { run }
      {% else %}
        spawn { run }
      {% end %}
    end

    private def signal_wakeup : Nil
      select
      when @wakeup.send(nil)
      else
      end
    end

    private def run : Nil
      loop do
        entry = @mutex.synchronize { @heap.first? }

        if entry.nil?
          @wakeup.receive
          next
        end

        remaining = entry.deadline - Time.instant
        if remaining > Time::Span.zero
          select
          when @wakeup.receive
            next
          when timeout(remaining)
          end
        end

        fire_due
      end
    end

    private def fire_due : Nil
      now = Time.instant
      due = [] of CancelSource

      @mutex.synchronize do
        while (entry = @heap.first?) && entry.deadline <= now
          due << pop.source
        end
      end

      due.each &.cancel(DEADLINE_EXCEEDED, by_deadline: true)
    end

    private def push(entry : Entry) : Nil
      @heap << entry
      sift_up(@heap.size - 1)
    end

    private def pop : Entry
      root = @heap.first
      last = @heap.pop
      unless @heap.empty?
        @heap[0] = last
        sift_down(0)
      end
      root
    end

    private def sift_up(index : Int32) : Nil
      while index > 0
        parent = (index - 1) // 2
        break if @heap[parent].deadline <= @heap[index].deadline
        @heap.swap(parent, index)
        index = parent
      end
    end

    private def sift_down(index : Int32) : Nil
      size = @heap.size

      loop do
        left = 2 * index + 1
        right = left + 1
        smallest = index
        smallest = left if left < size && @heap[left].deadline < @heap[smallest].deadline
        smallest = right if right < size && @heap[right].deadline < @heap[smallest].deadline
        break if smallest == index
        @heap.swap(index, smallest)
        index = smallest
      end
    end

    INSTANCE = new
  end
end
