require "../src/context"

ctx = Context.with_cancel
events = Channel(String).new
done = Channel(String).new
ready = Channel(Nil).new

spawn do
  begin
    ready.send(nil)
    event = Context.receive(ctx, events)
    done.send("received event: #{event}")
  rescue ex : Context::Cancelled
    done.send("receive stopped: #{ex.message}")
  end
end

ready.receive
ctx.cancel("client disconnected")

puts done.receive
