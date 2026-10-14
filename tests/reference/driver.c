#include "bsdiff.h"
#include "bspatch.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char *load(const char *name, size_t *size)
{
    FILE *f = fopen(name, "rb"); assert(f);
    assert(!fseek(f, 0, SEEK_END)); long n = ftell(f); assert(n >= 0);
    *size = (size_t)n; rewind(f);
    unsigned char *data = malloc(*size + 1); assert(data);
    assert(fread(data, 1, *size, f) == *size); fclose(f); return data;
}
static int write_patch(struct bsdiff_stream *s, const void *data, int size)
{ return fwrite(data, 1, (size_t)size, s->opaque) == (size_t)size ? 0 : -1; }
static int read_patch(const struct bspatch_stream *s, void *data, int size)
{ return fread(data, 1, (size_t)size, s->opaque) == (size_t)size ? 0 : -1; }
int main(int argc, char **argv)
{
    assert(argc >= 5);
    size_t oldsize; unsigned char *old = load(argv[2], &oldsize);
    if (!strcmp(argv[1], "diff")) {
        size_t newsize; unsigned char *newdata = load(argv[3], &newsize);
        FILE *f = fopen(argv[4], "wb"); assert(f);
        struct bsdiff_stream stream = {f, malloc, free, write_patch};
        assert(bsdiff(old, oldsize, newdata, newsize, &stream) == 0);
        assert(fclose(f) == 0); free(newdata);
    } else {
        assert(argc == 6 && !strcmp(argv[1], "patch"));
        long long size = strtoll(argv[5], NULL, 10); assert(size >= 0 && size <= 16777216);
        unsigned char *result = malloc((size_t)size + 1); assert(result);
        FILE *f = fopen(argv[3], "rb"); assert(f);
        struct bspatch_stream stream = {f, read_patch};
        assert(bspatch(old, oldsize, result, size, &stream) == 0);
        assert(fgetc(f) == EOF); fclose(f);
        f = fopen(argv[4], "wb"); assert(f);
        assert(fwrite(result, 1, (size_t)size, f) == (size_t)size);
        assert(fclose(f) == 0); free(result);
    }
    free(old); return 0;
}
