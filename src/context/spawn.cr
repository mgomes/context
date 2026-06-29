class Context
  # Spawns a fiber with a cancelable child context.
  def self.spawn(ctx : Context, &block : Context ->) : Fiber
    child = with_cancel(ctx)

    spawn do
      begin
        block.call(child)
      ensure
        child.cancel
      end
    end
  end
end
