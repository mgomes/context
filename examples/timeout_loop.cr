require "../src/context"

ctx = Context.with_timeout(100.milliseconds)

begin
  loop do
    ctx.checkpoint!
  end
rescue ex : Context::Cancelled
  puts ex.message
end
