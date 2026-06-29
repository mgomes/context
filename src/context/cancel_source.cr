require "weak_ref"

class Context
  private class CancelSource
    getter done

    @parent : CancelSource?
    @children : Array(WeakRef(CancelSource))
    @cancelled : Bool
    @reason : String?
    @by_deadline : Bool

    def initialize(@parent : CancelSource? = nil)
      @done = Channel(Nil).new
      @mutex = Mutex.new
      @children = [] of WeakRef(CancelSource)
      @cancelled = false
      @reason = nil
      @by_deadline = false
      @parent.try &.add_child(self)
    end

    def cancel(reason : String? = nil, by_deadline : Bool = false) : Bool
      children = [] of CancelSource
      parent = nil.as(CancelSource?)

      @mutex.synchronize do
        return false if @cancelled

        @cancelled = true
        @reason = reason
        @by_deadline = by_deadline
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
      children.each { |child| child.cancel(reason, by_deadline) }
      true
    end

    def cancelled? : Bool
      @mutex.synchronize { @cancelled }
    end

    def reason : String?
      @mutex.synchronize { @reason }
    end

    def by_deadline? : Bool
      @mutex.synchronize { @by_deadline }
    end

    protected def add_child(child : CancelSource) : Nil
      cancel_child = false
      reason = nil.as(String?)
      by_deadline = false

      @mutex.synchronize do
        if @cancelled
          cancel_child = true
          reason = @reason
          by_deadline = @by_deadline
        else
          prune_dead_children
          @children << WeakRef.new(child)
        end
      end

      child.cancel(reason, by_deadline) if cancel_child
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
