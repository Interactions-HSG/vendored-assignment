#include "ring.h"

/* Keep one slot empty so that head == tail always means empty, and a head one
 * behind tail means full. Simple, and no extra counter to keep in step. */

int ring_push(ring *r, int value) {
    unsigned next = (r->head + 1) % r->cap;
    if (next == r->tail) return -1;   /* full */
    r->slots[r->head] = value;
    r->head = next;
    return 0;
}

int ring_pop(ring *r, int *out) {
    if (r->head == r->tail) return -1;  /* empty */
    *out = r->slots[r->tail];
    r->tail = (r->tail + 1) % r->cap;
    return 0;
}
