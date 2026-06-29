class Context
  # Spawns a fiber with a cancelable child context.
  def self.spawn(ctx : Context, &block : Context ->) : Fiber
    child = with_cancel(ctx)

    spawn do
      run_spawned_child(child, block)
    end
  end

  {% if flag?(:execution_context) %}
    # Spawns a fiber into `execution_context` with a cancelable child context.
    def self.spawn(
      ctx : Context,
      *,
      execution_context : Fiber::ExecutionContext,
      &block : Context ->
    ) : Fiber
      child = with_cancel(ctx)

      execution_context.spawn do
        run_spawned_child(child, block)
      end
    end
  {% end %}

  private def self.run_spawned_child(child : Context, block : Context ->) : Nil
    block.call(child)
  ensure
    child.cancel
  end
end
