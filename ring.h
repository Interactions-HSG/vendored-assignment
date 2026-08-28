#ifndef RING_H
#define RING_H

typedef struct {
    int *slots;
    unsigned cap;
    unsigned head;
    unsigned tail;
} ring;

int ring_push(ring *r, int value);
int ring_pop(ring *r, int *out);

#endif
