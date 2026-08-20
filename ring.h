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
