/* A fixed-capacity ring buffer shared by one producer and one consumer.
 *
 * The allocation and the struct are settled. push and pop are the decision:
 * with head and tail alone, "empty" and "full" look identical, and what you do
 * about that is the assignment.
 */
#include "ring.h"

int ring_push(ring *r, int value) {
    (void)r; (void)value;
    return -1; /* not implemented */
}

int ring_pop(ring *r, int *out) {
    (void)r; (void)out;
    return -1; /* not implemented */
}
