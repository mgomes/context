# Go-style cooperative cancellation, deadlines, and blocking helpers for Crystal.
class Context
  DEFAULT_REASON    = "context cancelled"
  DEADLINE_EXCEEDED = "context deadline exceeded"

  # Raised by `Context#checkpoint!` and context-aware blocking helpers.
  class Cancelled < Exception
    # Creates a cancellation exception with a stable default message.
    def initialize(reason : String? = nil)
      super(reason || DEFAULT_REASON)
    end
  end

  # Raised instead of `Cancelled` when cancellation was caused by a deadline.
  #
  # `DeadlineExceeded` is a `Cancelled`, so `rescue Context::Cancelled` still
  # catches it; rescue `DeadlineExceeded` to distinguish timeouts from manual
  # cancellation.
  class DeadlineExceeded < Cancelled
  end
end
