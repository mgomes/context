require "../src/context"

jobs = Channel(Int32).new(8)
ctx = Context.with_cancel
done = Channel(String).new
progress = Channel(Int32).new

spawn do
  processed = [] of Int32

  begin
    loop do
      job = Context.receive(ctx, jobs)
      Context.sleep(ctx, 20.milliseconds)
      processed << job
      progress.send(processed.size)
    end
  rescue ex : Context::Cancelled
    done.send("worker stopped after #{processed.size} jobs: #{ex.message}")
  end
end

5.times do |index|
  jobs.send(index + 1)
end

2.times { progress.receive }
ctx.cancel("shutdown requested")

puts done.receive
