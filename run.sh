#!/bin/sh
# What the examiner may run against the submitted ring buffer.
#
# The submission is a library with no main of its own, so every target here is
# a small driver compiled against the candidate's ring.c. cc writes, and the
# checkout is not ours to write into, so everything is assembled in /build.
#
# The drivers hand the buffer a backing array larger than the capacity they
# tell it about, filled with a value no target ever pushes. An implementation
# that indexes without wrapping then writes into the slack instead of over
# something, and is caught by the leftover value being gone rather than by a
# crash that would have to be read as a signal death.
set -eu
mkdir -p "${TMPDIR:-/build/tmp}"

W=/build/viva-run

list() {
    printf '%s\t%s\n' ring \
        'Pushes and pops by hand through a buffer of 4 slots and prints what every call returned. The plain run: what their buffer does.'
    printf '%s\t%s\n' capacity \
        'Pushes into a buffer of capacity 4 until it is refused, and reports how many it took. Fails on the off-by-one that holds three, or five.'
    printf '%s\t%s\n' wrap \
        'A thousand pushes and pops through a buffer of 4, checking the values come back in order and that nothing was written past the last slot.'
    printf '%s\t%s\n' boundary \
        'Fills the buffer, then alternates one pop and one push twenty times, so head and tail meet away from zero. Fails if full and empty stop being told apart.'
}

# The candidate's ring.c, with the header they kept or the one they were handed.
prepare() {
    rm -rf "$W"
    mkdir -p "$W"
    [ -f /work/ring.c ] || { echo "the submission has no ring.c at its root"; exit 2; }
    cp /work/ring.c "$W/"
    if [ -f /work/ring.h ]; then
        cp /work/ring.h "$W/"
    else
        cat > "$W/ring.h" <<'HDR'
#ifndef RING_H
#define RING_H

typedef struct {
    int *slots;
    unsigned cap;
    unsigned head;
    unsigned tail;
} ring;

/* 0 on success, -1 if the buffer is full. */
int ring_push(ring *r, int value);
/* 0 on success, -1 if the buffer is empty. */
int ring_pop(ring *r, int *out);

#endif
HDR
    fi
}

TARGET="${1:-ring}"
if [ "$TARGET" = "--list" ]; then
    list
    exit 0
fi

prepare

case "$TARGET" in
ring)
    cat > "$W/viva_main.c" <<'SRC'
/* A short scripted session against the submitted buffer, call by call. */
#include <stdio.h>
#include "ring.h"

#define CAP   4
#define SLACK 64
static int mem[CAP + SLACK];

int main(void) {
    for (int i = 0; i < CAP + SLACK; i++) mem[i] = -1;
    /* Designated, so a submission that added a field to the struct still
       starts from an empty buffer rather than from whatever came next. */
    ring r = { .slots = mem, .cap = CAP };
    int out = 0, first = -1;

    printf("a buffer of %d slots, empty\n", CAP);
    for (int v = 1; v <= 5; v++) {
        int rc = ring_push(&r, v);
        if (v == 1) first = rc;
        printf("push %d -> %s\n", v, rc == 0 ? "ok" : "refused");
    }
    for (int i = 0; i < 3; i++) {
        if (ring_pop(&r, &out) == 0) printf("pop    -> %d\n", out);
        else                         printf("pop    -> refused\n");
    }
    for (int v = 6; v <= 8; v++)
        printf("push %d -> %s\n", v, ring_push(&r, v) == 0 ? "ok" : "refused");
    /* Counted rather than "until it refuses": a pop that always succeeds
       would otherwise print for as long as the examiner waited. */
    for (int i = 0; i < CAP + 2; i++) {
        if (ring_pop(&r, &out) == 0) { printf("pop    -> %d\n", out); continue; }
        printf("pop    -> refused (empty)\n");
        break;
    }
    if (first != 0) {
        printf("the first push into an empty buffer was refused\n");
        return 1;
    }
    return 0;
}
SRC
    ;;
capacity)
    cat > "$W/viva_main.c" <<'SRC'
/* Does the buffer hold what it says it holds? */
#include <stdio.h>
#include "ring.h"

#define CAP   4
#define SLACK 64
static int mem[CAP + SLACK];

int main(void) {
    for (int i = 0; i < CAP + SLACK; i++) mem[i] = -1;
    ring r = { .slots = mem, .cap = CAP };

    int pushed = 0;
    for (int i = 0; i < CAP + 8; i++) {
        if (ring_push(&r, i + 1) != 0) break;
        pushed++;
    }
    printf("capacity %d, pushed until refused: %d\n", CAP, pushed);

    int popped = 0, out = 0;
    for (int i = 0; i < CAP + 8; i++) {
        if (ring_pop(&r, &out) != 0) break;
        popped++;
    }
    printf("popped back out:                 %d\n", popped);

    int over = -1;
    for (int i = CAP; i < CAP + SLACK; i++) {
        if (mem[i] != -1) { over = i; break; }
    }
    if (over >= 0)
        printf("wrote to slot %d of a %d-slot buffer\n", over, CAP);

    int ok = pushed == CAP && popped == CAP && over < 0;
    printf("%s\n", ok ? "holds its stated capacity"
                      : "DOES NOT hold its stated capacity");
    return ok ? 0 : 1;
}
SRC
    ;;
wrap)
    cat > "$W/viva_main.c" <<'SRC'
/* Push and pop past the end of the array, many times over. */
#include <stdio.h>
#include "ring.h"

#define CAP    4
/* Enough room for every push a non-wrapping implementation would make, so it
   lands in the slack and is reported rather than dying on a signal. */
#define SLACK  2048
#define ROUNDS 1000
static int mem[CAP + SLACK];

int main(void) {
    for (int i = 0; i < CAP + SLACK; i++) mem[i] = -1;
    ring r = { .slots = mem, .cap = CAP };

    int out = 0, ok = 1;
    for (int i = 0; i < ROUNDS; i++) {
        if (ring_push(&r, i + 1) != 0) { printf("refused a push at %d\n", i); ok = 0; break; }
        if (ring_pop(&r, &out) != 0)   { printf("refused a pop at %d\n", i);  ok = 0; break; }
        if (out != i + 1) { printf("got %d back at %d, expected %d\n", out, i, i + 1); ok = 0; break; }
    }

    for (int i = CAP; i < CAP + SLACK; i++) {
        if (mem[i] == -1) continue;
        printf("wrote to slot %d of a %d-slot buffer: the indices do not wrap\n", i, CAP);
        ok = 0;
        break;
    }
    printf("%s\n", ok ? "1000 wraps, values came back in order and stayed inside the buffer"
                      : "the buffer did not survive wrapping");
    return ok ? 0 : 1;
}
SRC
    ;;
boundary)
    cat > "$W/viva_main.c" <<'SRC'
/* Full, then held full while head and tail travel: the state where a buffer
   that cannot separate full from empty starts refusing or losing values. */
#include <stdio.h>
#include "ring.h"

#define CAP    4
#define SLACK  64
#define CYCLES 20
static int mem[CAP + SLACK];

int main(void) {
    for (int i = 0; i < CAP + SLACK; i++) mem[i] = -1;
    ring r = { .slots = mem, .cap = CAP };

    int ok = 1, out = 0, next = 1, expect = 1, filled = 0, cycles = 0;

    for (int i = 0; i < CAP; i++) {
        if (ring_push(&r, next++) == 0) { filled++; continue; }
        printf("refused push %d while filling an empty buffer\n", next - 1);
        ok = 0;
    }
    if (ring_push(&r, 999) == 0) { printf("accepted a push into a full buffer\n"); ok = 0; }
    printf("filled %d of %d slots\n", filled, CAP);

    for (int i = 0; i < CYCLES; i++) {
        if (ring_pop(&r, &out) != 0) {
            printf("refused a pop at cycle %d, with a full buffer\n", i); ok = 0; break;
        }
        if (out != expect) {
            printf("cycle %d popped %d, expected %d\n", i, out, expect); ok = 0; break;
        }
        expect++;
        if (ring_push(&r, next++) != 0) {
            printf("refused a push at cycle %d, one slot having just been freed\n", i); ok = 0; break;
        }
        cycles++;
    }
    printf("%d pop-then-push cycles done\n", cycles);

    /* Only worth draining a buffer that survived the cycles: after a failure
       the contents are whatever the failure left, and reporting on them says
       the same thing twice. */
    if (ok) {
        int drained = 0;
        for (int i = 0; i < CAP + SLACK; i++) {
            if (ring_pop(&r, &out) != 0) break;
            drained++;
            if (out == expect) { expect++; continue; }
            printf("draining gave %d, expected %d\n", out, expect);
            ok = 0;
            break;
        }
        if (drained != CAP) { printf("drained %d after the cycles, expected %d\n", drained, CAP); ok = 0; }

        for (int i = CAP; i < CAP + SLACK; i++) {
            if (mem[i] == -1) continue;
            printf("wrote to slot %d of a %d-slot buffer\n", i, CAP);
            ok = 0;
            break;
        }
    }
    printf("%s\n", ok ? "full and empty are still told apart away from zero"
                      : "FULL AND EMPTY ARE NOT TOLD APART");
    return ok ? 0 : 1;
}
SRC
    ;;
*)
    printf 'no such target: %s\n' "$TARGET" >&2
    list >&2
    exit 2
    ;;
esac

cd "$W"
cc -std=c11 -Wall -O1 -I. -I/opt/vendor -o viva_run viva_main.c ring.c 2>&1 || exit 1
./viva_run
