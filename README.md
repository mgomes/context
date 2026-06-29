# context

`context` is a Crystal shard prototype for Go-style cooperative cancellation and
deadlines.

Requires Crystal 1.20.2 or newer.

It is intentionally explicit: pass `ctx : Context` through the work that should
observe cancellation, then call `ctx.checkpoint!` at cooperative boundaries.

```crystal
ctx = Context.with_timeout(100.milliseconds)

loop do
  ctx.checkpoint!
  do_work
end
```

The initial prototype includes:

- `Context.background`
- `Context.with_cancel`
- `Context.with_timeout`
- `ctx.cancel`
- `ctx.cancelled?`
- `ctx.reason`
- `ctx.deadline`
- `ctx.checkpoint!`
- parent-child cancellation propagation
- `Context.sleep(ctx, duration)`
- `Context.receive(ctx, channel)`

Cancellation is cooperative. This shard does not forcibly preempt arbitrary
Crystal code, enforce memory limits, or replace process and container sandboxing.
