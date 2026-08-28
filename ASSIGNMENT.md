# One producer, one consumer (example assignment)

A fixed-capacity buffer between two threads. One pushes, one pops. With only a
head and a tail, "empty" and "full" look the same — that is your problem.

Your problem is `ring.c`, and two functions in it.

## What to do

1. **`ring_push(r, value)`** — 0 on success, -1 if full.
2. **`ring_pop(r, &out)`** — 0 on success, -1 if empty.

## What you are marked on

Whether you can explain the arithmetic in a viva. The examiner can compile and
run your buffer.
