# context

`context` is a Crystal shard for cooperative cancellation, deadlines, and
request-scoped values. It answers one question for running work:

> Should this work still be allowed to continue?

It does not decide where a fiber runs. It does not forcibly stop arbitrary
Crystal code. It gives code a small, explicit handle it can pass down the stack
and check at blocking or CPU-bound cooperative boundaries.

Requires Crystal 1.20.2 or newer.

## What This Provides

Use `Context` when a request, job, sandbox, or worker needs a shared lifetime.
The current prototype supports:

- root contexts with `Context.background`
- manual cancellation with `Context.with_cancel`
- deadlines with `Context.with_timeout` and `Context.with_deadline`
- cancellation reasons with `ctx.reason`
- cooperative checkpoints with `ctx.checkpoint!`
- parent-to-child cancellation propagation
- request-scoped values with `ctx.with_value` and `ctx.value`
- child fiber creation with `Context.spawn(ctx)`
- optional execution-context placement with `Context.spawn(ctx, execution_context: ec)`
- context-aware `sleep`, channel `receive`, and channel `send`
- a `ctx.done` channel for composing your own `select`
- `Context::DeadlineExceeded` to tell timeouts apart from manual cancellation

The handle is explicit by design:

```crystal
ctx = Context.with_timeout(100.milliseconds)

loop do
  ctx.checkpoint!
  do_work
end
```

## Execution Contexts

Crystal execution contexts answer where a fiber runs. `Context` answers whether
the work should still continue.

The core shard does not require execution contexts. When compiling with
Crystal's preview execution-context flags, `Context.spawn` can place child work
into a specific `Fiber::ExecutionContext` while keeping the same cancellation,
deadline, and value propagation rules:

```crystal
sandbox_ec = Fiber::ExecutionContext::Parallel.new("sandbox", 1)

Context.spawn(ctx, execution_context: sandbox_ec) do |child_ctx|
  run_sandbox(child_ctx)
end
```

This API is compiled only when Crystal's execution-context preview is enabled.
Without those flags, `Context.spawn(ctx)` uses Crystal's normal `spawn` and
inherits the current runtime placement. Cancellation semantics stay the same in
both modes.

## How Cancellation Works

Cancellation is cooperative. Code stops when it calls `ctx.checkpoint!` or uses a
context-aware wrapper such as `Context.sleep`, `Context.receive`, or
`Context.send`.

Child contexts inherit parent cancellation:

```crystal
parent = Context.with_cancel
child = Context.with_timeout(parent, 1.second)

parent.cancel("client disconnected")
child.checkpoint! # raises Context::Cancelled
```

Deadlines use the earliest deadline in the parent-child chain. Manual
cancellation and deadline cancellation are both idempotent; the first reason
wins.

Deadline cancellation raises `Context::DeadlineExceeded`, a subclass of
`Context::Cancelled`. Rescue the base class to handle any cancellation, or the
subclass to single out timeouts:

```crystal
begin
  ctx.checkpoint!
rescue Context::DeadlineExceeded
  # deadline expired
rescue Context::Cancelled
  # canceled for some other reason
end
```

Deadlines are tracked against a monotonic clock (`Time.instant`), so a system
clock adjustment will not move when a deadline fires. `Context.with_deadline`
accepts a wall-clock `Time` and converts it to a monotonic instant once, at
creation. `ctx.deadline` returns that `Time::Instant`.

## Composing With `done`

`ctx.done` returns a channel that closes when the context is canceled. Use it to
build your own `select` over a context plus your own channels:

```crystal
select
when value = work.receive
  handle(value)
when ctx.done.receive?
  ctx.checkpoint! # raises Context::Cancelled with the reason
end
```

The channel is receive-only: never send to it or close it. A context with no
cancellation source (`Context.background`) returns a channel that never closes.

## Values Are Typed

Context values are for request-scoped metadata such as request IDs, sandbox IDs,
or trace IDs. Symbol keys are convenient, and typed keys avoid accidental type
collisions:

```crystal
request_id = Context::Key(String).new(:request_id)

ctx = Context.background
  .with_value(:sandbox_id, "sandbox-7")
  .with_value(request_id, "req-9")

ctx.value(:sandbox_id, String) # => "sandbox-7"
ctx.value(request_id)          # => "req-9"
```

`with_value` does not create a new cancellation scope: the returned context
shares its parent's cancellation source, so canceling it cancels the parent and
its other descendants. Use `with_cancel` when you need an independent lifetime.

## What This Does Not Do

This shard cannot preempt code that never cooperates.

This will stop:

```crystal
loop do
  ctx.checkpoint!
  execute_next_instruction
end
```

This will not:

```crystal
while true
end
```

Hard sandbox termination still belongs below this layer: process isolation,
containers, microVMs, OS limits, or runtime support. `Context` is semantic
lifetime control, not a resource-limit mechanism.

## Examples

The runnable examples cover the cancellation boundaries this shard is meant to
make boring:

- `channel_receive`: a fiber blocked on `Context.receive` wakes when canceled
- `cooperative_worker`: a worker loop exits at context-aware boundaries
- `sandbox_interpreter`: an interpreter loop stops at a deadline checkpoint
- `timeout_loop`: the smallest tight-loop checkpoint smoke test

Run them with:

```sh
shards run channel_receive
shards run cooperative_worker
shards run sandbox_interpreter
shards run timeout_loop
```

See [examples/README.md](examples/README.md) for expected output.

## Verification

Run the full suite with:

```sh
crystal spec --error-on-warnings
```

The suite currently covers 54 examples across:

- focused context behavior specs
- edge and race specs for deadlines, cancellation, channels, values, and spawn
- executable example specs that run each example with `crystal run`
- integration specs that pass contexts through service-style stacks, nested
  timeouts, worker fibers, and cooperative sandbox checkpoints

Build every runnable shard target with:

```sh
shards build --error-on-warnings
```

Run the optional execution-context integration spec on its own with:

```sh
crystal spec --error-on-warnings -Dpreview_mt -Dexecution_context spec/execution_context_spec.cr
```

Run the full suite with the preview flags to get all 55 examples (the 54 above
plus the execution-context integration spec):

```sh
crystal spec --error-on-warnings -Dpreview_mt -Dexecution_context
```

## License

MIT. See [LICENSE](LICENSE).
