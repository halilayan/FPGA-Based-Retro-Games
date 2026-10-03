/*
 * sys.c -- shared logic for sys.h: tick counter, RNG, and a minimal
 * printf-style formatter (see sys.h for why it exists instead of vsnprintf).
 */
#include "sys.h"
#include <stdarg.h>

static uint32_t tick_count;
static uint32_t lfsr_state = 1;  /* never 0 - a Fibonacci LFSR locks up at 0 */

void sys_init(void)
{
    tick_count = 0;
    lfsr_state = 1;
}

void sys_poll(void)
{
    tick_count++;
}

uint32_t sys_ticks(void)
{
    return tick_count;
}

void sys_srand(uint32_t seed)
{
    lfsr_state = (seed != 0u) ? seed : 1u;
}

uint32_t sys_rng(void)
{
    uint32_t bit = ((lfsr_state >> 31) & 1u) ^ ((lfsr_state >> 21) & 1u) ^
                   ((lfsr_state >> 1) & 1u) ^ (lfsr_state & 1u);
    lfsr_state = (lfsr_state << 1) | bit;
    return lfsr_state;
}

/* ---- minimal formatter, see sys.h for why this exists instead of vsnprintf ---- */

static char *put_char(char *dst, const char *end, char c)
{
    if (dst < end) {
        *dst = c;
        dst++;
    }
    return dst;
}

static char *put_str(char *dst, const char *end, const char *s)
{
    while (*s != '\0') {
        dst = put_char(dst, end, *s);
        s++;
    }
    return dst;
}

static char *put_udec(char *dst, const char *end, unsigned long v)
{
    char tmp[12]; /* enough digits for a 32-bit value (10) plus margin */
    int n = 0;

    if (v == 0u) {
        return put_char(dst, end, '0');
    }
    while (v > 0u && n < (int)sizeof(tmp)) {
        tmp[n] = (char)('0' + (v % 10u));
        n++;
        v /= 10u;
    }
    while (n > 0) {
        n--;
        dst = put_char(dst, end, tmp[n]);
    }
    return dst;
}

static char *put_sdec(char *dst, const char *end, long v)
{
    if (v < 0) {
        dst = put_char(dst, end, '-');
        v = -v;
    }
    return put_udec(dst, end, (unsigned long)v);
}

static char *put_hex(char *dst, const char *end, unsigned long v, int width, int upper)
{
    static const char DIGITS_LOWER[] = "0123456789abcdef";
    static const char DIGITS_UPPER[] = "0123456789ABCDEF";
    const char *digits = upper ? DIGITS_UPPER : DIGITS_LOWER;
    char tmp[8]; /* a 32-bit value is at most 8 hex digits */
    int n = 0;

    if (v == 0u) {
        tmp[n] = '0';
        n++;
    }
    while (v > 0u && n < (int)sizeof(tmp)) {
        tmp[n] = digits[v & 0xFu];
        n++;
        v >>= 4;
    }
    while (n < width && n < (int)sizeof(tmp)) {
        tmp[n] = '0';
        n++;
    }
    while (n > 0) {
        n--;
        dst = put_char(dst, end, tmp[n]);
    }
    return dst;
}

static void format_v(char *buf, int buf_size, const char *fmt, va_list ap)
{
    char *dst = buf;
    const char *end = buf + buf_size - 1;  /* leave room for the NUL */
    int width;
    int is_long;

    while (*fmt != '\0') {
        if (*fmt != '%') {
            dst = put_char(dst, end, *fmt);
            fmt++;
            continue;
        }
        fmt++;  /* skip '%' */

        width = 0;
        if (*fmt == '0') {
            fmt++;  /* leading-zero flag: always zero-pads, so just consumed */
        }
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + (*fmt - '0');
            fmt++;
        }

        is_long = 0;
        if (*fmt == 'l') {
            is_long = 1;
            fmt++;
        }

        switch (*fmt) {
            case 'd':
                if (is_long) {
                    dst = put_sdec(dst, end, va_arg(ap, long));
                } else {
                    dst = put_sdec(dst, end, (long)va_arg(ap, int));
                }
                break;
            case 'u':
                if (is_long) {
                    dst = put_udec(dst, end, va_arg(ap, unsigned long));
                } else {
                    dst = put_udec(dst, end, (unsigned long)va_arg(ap, unsigned int));
                }
                break;
            case 'x':
            case 'X':
                if (is_long) {
                    dst = put_hex(dst, end, va_arg(ap, unsigned long), width, *fmt == 'X');
                } else {
                    dst = put_hex(dst, end, (unsigned long)va_arg(ap, unsigned int), width, *fmt == 'X');
                }
                break;
            case 's':
                dst = put_str(dst, end, va_arg(ap, const char *));
                break;
            case '%':
                dst = put_char(dst, end, '%');
                break;
            default:
                /* unrecognised specifier: emit it literally so a mistake is visible */
                dst = put_char(dst, end, '%');
                if (*fmt != '\0') {
                    dst = put_char(dst, end, *fmt);
                }
                break;
        }

        if (*fmt != '\0') {
            fmt++;
        }
    }
    *dst = '\0';
}

void sys_format(char *buf, int buf_size, const char *fmt, ...)
{
    va_list ap;

    va_start(ap, fmt);
    format_v(buf, buf_size, fmt, ap);
    va_end(ap);
}

void sys_log(const char *fmt, ...)
{
    char buf[128];
    va_list ap;

    va_start(ap, fmt);
    format_v(buf, sizeof buf, fmt, ap);
    va_end(ap);

    sys_write_str(buf);
}
