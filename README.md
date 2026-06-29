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

## Examples

The `examples/` directory includes runnable examples for realistic cancellation
boundaries:

- `channel_receive`: cancel a fiber blocked on a channel receive
- `cooperative_worker`: stop a worker loop at context-aware boundaries
- `sandbox_interpreter`: enforce a deadline in a small interpreter loop
- `timeout_loop`: minimal tight-loop checkpoint smoke test

Run them with `shards run <name>`. See [examples/README.md](examples/README.md)
for expected output and scenario notes.

The spec suite also runs each example with `crystal run --error-on-warnings` and
asserts its output, so examples stay aligned with the public API.

## Testing

Run the full suite with:

```sh
crystal spec
```

The suite includes focused context behavior specs, runnable example specs, and
integration specs that pass contexts through service-style stacks, nested
timeouts, worker fibers, and cooperative sandbox checkpoints.
