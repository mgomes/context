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
end
