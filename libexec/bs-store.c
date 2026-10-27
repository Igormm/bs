/* bs-store.c — minimal file-backed key-value store for the BS framework.
 *
 * An OPTIONAL backend for core/store.sh: the in-memory store (__bs_store_v_*)
 * does not survive across processes; this helper persists values in a plain
 * file so `bs_store_*` can share state between invocations. It stores and
 * retrieves VALUES ONLY — the schema, @ops and validation stay in the shell
 * layer (single source of truth), so this file has no knowledge of them.
 *
 * Usage:
 *   bs-store set   FILE NAME   # value is read from stdin (one line, no \n)
 *   bs-store get   FILE NAME   # prints the value
 *   bs-store has   FILE NAME   # prints 1/0, exit 0/1
 *   bs-store unset FILE NAME
 *   bs-store list  FILE        # prints the names, one per line
 *
 * File format: one entry per line, NAME<TAB>VALUE. Names are
 * [A-Za-z_][A-Za-z0-9_]*; values hold no newline (a line is the protocol unit).
 * Writes are atomic: temp file in the same directory + rename, mode 0600.
 *
 * Exit codes: 0 ok, 1 not found, 2 usage, 3 I/O error.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>

#define BUF_MAX (1u << 20) /* 1 MiB, name+value */

static char g_buf[BUF_MAX];  /* the whole file */
static size_t g_len;
static char g_val[BUF_MAX];  /* a value read from stdin */

static int load(const char *path) {
    FILE *f = fopen(path, "rb");
    size_t n;
    if (!f) {
        if (errno == ENOENT) { g_len = 0; g_buf[0] = '\0'; return 0; }
        perror("bs-store: open");
        return 3;
    }
    n = fread(g_buf, 1, BUF_MAX - 1, f);
    if (ferror(f)) { perror("bs-store: read"); fclose(f); return 3; }
    g_buf[n] = '\0';
    g_len = n;
    fclose(f);
    return 0;
}

static int save(const char *path) {
    size_t plen = strlen(path);
    char tmp[4096];
    int fd;
    size_t off = 0;
    if (plen + 32 >= sizeof(tmp)) { fprintf(stderr, "bs-store: path too long\n"); return 3; }
    snprintf(tmp, sizeof(tmp), "%s.tmp.%ld", path, (long)getpid());
    fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) { perror("bs-store: create"); return 3; }
    while (off < g_len) {
        ssize_t w = write(fd, g_buf + off, g_len - off);
        if (w < 0) { perror("bs-store: write"); close(fd); unlink(tmp); return 3; }
        off += (size_t)w;
    }
    if (close(fd) != 0) { perror("bs-store: close"); unlink(tmp); return 3; }
    if (rename(tmp, path) != 0) { perror("bs-store: rename"); unlink(tmp); return 3; }
    return 0;
}

static char *find(const char *name, size_t *vlen) {
    size_t nlen = strlen(name);
    char *p = g_buf;
    while (p < g_buf + g_len) {
        char *nl = memchr(p, '\n', (size_t)(g_buf + g_len - p));
        char *end = nl ? nl : g_buf + g_len;
        if ((size_t)(end - p) >= nlen + 1 && memcmp(p, name, nlen) == 0 && p[nlen] == '\t') {
            *vlen = (size_t)(end - (p + nlen + 1));
            return p + nlen + 1;
        }
        p = nl ? nl + 1 : g_buf + g_len;
    }
    return NULL;
}

static int del(const char *name) {
    size_t nlen = strlen(name);
    char *p = g_buf;
    while (p < g_buf + g_len) {
        char *nl = memchr(p, '\n', (size_t)(g_buf + g_len - p));
        char *end = nl ? nl : g_buf + g_len;
        if ((size_t)(end - p) >= nlen + 1 && memcmp(p, name, nlen) == 0 && p[nlen] == '\t') {
            char *next = nl ? nl + 1 : g_buf + g_len;
            memmove(p, next, (size_t)(g_buf + g_len - next));
            g_len -= (size_t)(next - p);
            return 0;
        }
        p = nl ? nl + 1 : g_buf + g_len;
    }
    return 0;
}

static int set(const char *path, const char *name) {
    size_t nlen = strlen(name), vlen;
    if (!fgets(g_val, BUF_MAX, stdin)) g_val[0] = '\0';
    vlen = strlen(g_val);
    while (vlen && (g_val[vlen - 1] == '\n' || g_val[vlen - 1] == '\r')) g_val[--vlen] = '\0';
    if (memchr(g_val, '\n', vlen)) { fprintf(stderr, "bs-store: value must not contain a newline\n"); return 2; }
    del(name);
    if (g_len + nlen + 1 + vlen + 1 >= BUF_MAX) { fprintf(stderr, "bs-store: entry too large\n"); return 3; }
    {
        char *dst = g_buf + g_len;
        memcpy(dst, name, nlen); dst += nlen;
        *dst++ = '\t';
        if (vlen) { memcpy(dst, g_val, vlen); dst += vlen; }
        *dst++ = '\n';
        g_len = (size_t)(dst - g_buf);
    }
    return save(path);
}

int main(int argc, char **argv) {
    const char *cmd, *path, *name;
    if (argc < 3) {
        fprintf(stderr, "usage: bs-store {set|get|has|unset|list} FILE [NAME]\n");
        return 2;
    }
    cmd = argv[1];
    path = argv[2];
    name = argc >= 4 ? argv[3] : NULL;

    if (strcmp(cmd, "set") == 0 && name) {
        int rc = load(path);
        if (rc) return rc;
        return set(path, name);
    }
    if (strcmp(cmd, "get") == 0 && name) {
        size_t vlen;
        char *v;
        int rc = load(path);
        if (rc) return rc;
        v = find(name, &vlen);
        if (!v) return 1;
        fwrite(v, 1, vlen, stdout);
        putchar('\n');
        return 0;
    }
    if (strcmp(cmd, "has") == 0 && name) {
        size_t vlen;
        int rc = load(path);
        if (rc) return rc;
        if (find(name, &vlen)) { puts("1"); return 0; }
        puts("0"); return 1;
    }
    if (strcmp(cmd, "unset") == 0 && name) {
        int rc = load(path);
        if (rc) return rc;
        del(name);
        return save(path);
    }
    if (strcmp(cmd, "list") == 0) {
        int rc = load(path);
        char *p;
        if (rc) return rc;
        p = g_buf;
        while (p < g_buf + g_len) {
            char *tab = memchr(p, '\t', (size_t)(g_buf + g_len - p));
            if (tab) { fwrite(p, 1, (size_t)(tab - p), stdout); putchar('\n'); }
            char *nl = memchr(p, '\n', (size_t)(g_buf + g_len - p));
            p = nl ? nl + 1 : g_buf + g_len;
        }
        return 0;
    }
    fprintf(stderr, "bs-store: unknown command: %s\n", cmd);
    return 2;
}
