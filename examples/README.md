# Examples

These examples are executable shard targets. Run them with:

```sh
shards run channel_receive
shards run cooperative_worker
shards run sandbox_interpreter
shards run timeout_loop
```

They also run as part of `crystal spec`.

## `channel_receive`

Shows a fiber blocked on `Context.receive(ctx, channel)` waking when the context
is canceled. This is the shape used for request-scoped consumers waiting on work
that may never arrive.

Expected output:

```text
receive stopped: client disconnected
```

## `cooperative_worker`

Shows a worker loop receiving jobs, doing context-aware sleeps, and exiting when
its parent context is canceled. This demonstrates the normal service-worker
pattern: every blocking boundary is context-aware.

Expected output:

```text
worker stopped after 2 jobs: shutdown requested
```

## `sandbox_interpreter`

Shows a tiny interpreter loop that checks `ctx.checkpoint!` before each
instruction and during CPU-bound spin work. The deadline stops the program at a
cooperative boundary and surfaces the cancellation reason.

Expected output:

```text
sandbox stopped: context deadline exceeded; accumulator=110
```

## `timeout_loop`

Shows the smallest possible deadline checkpoint loop. It is intentionally tiny
and exists as a smoke test for tight cooperative loops.

Expected output:

```text
context deadline exceeded
```
