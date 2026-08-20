#!/bin/sh
# Does the submitted C build? The answer a patch is admitted on.
#
# Every .c at the root of the checkout is compiled on its own, so a submission
# that carries a main of its own is still built rather than colliding with one
# of ours. The two entry points are then linked against a stub that calls them,
# because a body deleted by a patch compiles perfectly well as an object and
# only goes missing at link time, which the examiner would otherwise meet as a
# run that never started.
#
# cc writes beside its input by default and the checkout is not ours to write
# into, so every artefact is named into /build.
set -eu
mkdir -p "${TMPDIR:-/build/tmp}"

W=/build/viva-compile
rm -rf "$W"
mkdir -p "$W"

[ -f /work/ring.c ] || { echo "the submission has no ring.c at its root"; exit 2; }

# The header they kept, or the one they were handed.
if [ ! -f /work/ring.h ]; then
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

CFLAGS="-std=c11 -Wall -O1"
INCLUDE="-I/work -I$W -I/opt/vendor"

status=0
for src in /work/*.c; do
    [ -f "$src" ] || continue
    obj="$W/$(basename "$src" .c).o"
    # shellcheck disable=SC2086
    cc $CFLAGS $INCLUDE -c "$src" -o "$obj" 2>&1 || status=1
done
[ "$status" -eq 0 ] || exit "$status"

cat > "$W/viva_link.c" <<'SRC'
/* Never run: it exists so that an entry point the assignment declares but the
   submission does not define is a build failure with a name attached. */
#include "ring.h"

int main(void) {
    ring r = { 0 };
    int value = 0;
    return ring_push(&r, 0) + ring_pop(&r, &value);
}
SRC

# shellcheck disable=SC2086
cc $CFLAGS $INCLUDE -c "$W/viva_link.c" -o "$W/viva_link.o" 2>&1 || exit 1
cc -o "$W/viva_link" "$W/viva_link.o" "$W/ring.o" 2>&1 || exit 1

echo "the submission builds"
