class Context
  # Typed key for request-scoped context values.
  struct Key(T)
    # Returns the human-readable key name.
    getter name

    # Creates a typed context value key.
    def initialize(name : String | Symbol)
      @name = name.to_s
    end
  end

  private record ValueKey, name : String, type_name : String

  private abstract class ValueBox
  end

  private class TypedValueBox(T) < ValueBox
    getter value

    def initialize(@value : T)
    end
  end

  # Returns a copy of this context with a typed request-scoped value.
  def with_value(key : Key(T), value : T) : Context forall T
    next_values = @values.dup
    next_values[value_key(key)] = TypedValueBox(T).new(value)
    Context.new(@source, @deadline, next_values)
  end

  # Returns a copy of this context with a symbol-keyed request-scoped value.
  def with_value(key : Symbol, value : T) : Context forall T
    with_value(Key(T).new(key), value)
  end

  # Returns a typed request-scoped value, if present.
  def value(key : Key(T)) : T? forall T
    box = @values[value_key(key)]?
    box.as?(TypedValueBox(T)).try &.value
  end

  # Returns a symbol-keyed request-scoped value, if present.
  def value(key : Symbol, type : T.class) : T? forall T
    value(Key(T).new(key))
  end

  private def value_key(key : Key(T)) : ValueKey forall T
    ValueKey.new(key.name, T.name)
  end
end
