// Extensive parts of this code is taken from `hiredis-rb`, so we're keeping the
// initial copyright:
//
// Copyright (c) 2010-2012, Pieter Noordhuis
//
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
//
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// * Neither the name of Redis nor the names of its contributors may be used to
//   endorse or promote products derived from this software without specific prior
//   written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include "ruby.h"
#include "ruby/thread.h"
#include "ruby/encoding.h"
#include <errno.h>
#include <sys/socket.h>
#include <stdbool.h>
#include "hiredis.h"
#include "net.h"
#include "hiredis_ssl.h"
#include <poll.h>

#if !defined(RUBY_ASSERT)
#  define RUBY_ASSERT(condition) ((void)0)
#endif

#if !defined(HAVE_RB_HASH_NEW_CAPA)
static inline VALUE rb_hash_new_capa(long capa)
{
  return rb_hash_new();
}
#endif

static void redis_set_error(redisContext *c, int type, const char *str) {
    size_t len;

    c->err = type;
    len = strlen(str);
    len = len < (sizeof(c->errstr) - 1) ? len : (sizeof(c->errstr) - 1);
    memcpy(c->errstr, str, len);
    c->errstr[len] = '\0';
}

static VALUE rb_eRedisClientCommandError, rb_eRedisClientConnectionError, rb_eRedisClientCannotConnectError, rb_eRedisClientProtocolError;
static VALUE rb_eRedisClientReadTimeoutError, rb_eRedisClientWriteTimeoutError;
static VALUE Redis_Qfalse;
static ID id_parse;

typedef struct {
    redisSSLContext *context;
} hiredis_ssl_context_t;

#define ENSURE_CONNECTED(connection) if (!connection->context) rb_raise(rb_eRedisClientConnectionError, "Not connected");

#define SSL_CONTEXT(from, name) \
    hiredis_ssl_context_t *name = NULL; \
    TypedData_Get_Struct(from, hiredis_ssl_context_t, &hiredis_ssl_context_data_type, name); \
    if (name == NULL) { \
        rb_raise(rb_eArgError, "NULL found for " # name " when shouldn't be."); \
    }

static void hiredis_ssl_context_free(void *ptr) {
    hiredis_ssl_context_t *ssl_context = (hiredis_ssl_context_t *)ptr;
    if (ssl_context->context) {
        redisFreeSSLContext(ssl_context->context);
        ssl_context = NULL;
    }
}

static size_t hiredis_ssl_context_memsize(const void *ptr) {
    size_t size = sizeof(hiredis_ssl_context_t);
    // Note: I couldn't find a way to measure the SSLContext size.
    return size;
}

static const rb_data_type_t hiredis_ssl_context_data_type = {
    .wrap_struct_name = "redis-client:hiredis_ssl_context",
    .function = {
        .dmark = NULL,
        .dfree = hiredis_ssl_context_free,
        .dsize = hiredis_ssl_context_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE hiredis_ssl_context_alloc(VALUE klass) {
    hiredis_ssl_context_t *ssl_context;
    return TypedData_Make_Struct(klass, hiredis_ssl_context_t, &hiredis_ssl_context_data_type, ssl_context);
}

static VALUE hiredis_ssl_context_init(VALUE self, VALUE ca_file, VALUE ca_path, VALUE cert, VALUE key, VALUE hostname) {
    redisSSLContextError ssl_error = 0;
    SSL_CONTEXT(self, ssl_context);

    ssl_context->context = redisCreateSSLContext(
        RTEST(ca_file) ? StringValueCStr(ca_file) : NULL,
        RTEST(ca_path) ? StringValueCStr(ca_path) : NULL,
        RTEST(cert) ? StringValueCStr(cert) : NULL,
        RTEST(key) ? StringValueCStr(key) : NULL,
        RTEST(hostname) ? StringValueCStr(hostname) : NULL,
        &ssl_error
    );

    if (ssl_error) {
        return rb_str_new_cstr(redisSSLContextGetError(ssl_error));
    }

    if (!ssl_context->context) {
        return rb_str_new_cstr("Unknown error while creating SSLContext");
    }

    return Qnil;
}

typedef struct {
    VALUE stack;
    int *task_index;
} hiredis_reader_state_t;

static void *reply_append(const redisReadTask *task, VALUE value) {
    hiredis_reader_state_t *state = (hiredis_reader_state_t *)task->privdata;
    int task_index = *state->task_index;

    if (task->parent) {
        RUBY_ASSERT(task_index > 0);
        VALUE parent = rb_ary_entry(state->stack, task_index - 1);
        switch (task->parent->type) {
            case REDIS_REPLY_ARRAY:
            case REDIS_REPLY_SET:
            case REDIS_REPLY_PUSH:
                rb_ary_store(parent, task->idx, value);
                break;
            case REDIS_REPLY_MAP:
                if (task->idx % 2) {
                    VALUE key = rb_ary_pop(state->stack);
                    rb_hash_aset(parent, key, value);
                    RB_GC_GUARD(key);
                } else {
                    rb_ary_push(state->stack, value);
                }
                break;
            default:
                rb_bug("[hiredis] Unexpected task parent type %d", task->parent->type);
                break;
        }
        RB_GC_GUARD(parent);
    }
    rb_ary_store(state->stack, task_index, value);
    RB_GC_GUARD(value);
    return (void*)value;
}

static void *reply_create_string(const redisReadTask *task, char *cstr, size_t len) {
    if (len >= 4 && task->type == REDIS_REPLY_VERB) {
        // Skip 4 bytes of verbatim type header.
        cstr += 4;
        len -= 4;
    }

    VALUE string = rb_utf8_str_new(cstr, len);
    if (rb_enc_str_coderange(string) == ENC_CODERANGE_BROKEN) {
        rb_enc_associate(string, rb_ascii8bit_encoding());
    }

    if (task->type == REDIS_REPLY_STATUS) {
      rb_str_freeze(string);
    }

    if (task->type == REDIS_REPLY_ERROR) {
        string = rb_funcall(rb_eRedisClientCommandError, id_parse, 1, string);
    }

    return reply_append(task, string);
}
static void *reply_create_array(const redisReadTask *task, size_t elements) {
    VALUE value = Qnil;
    switch (task->type) {
        case REDIS_REPLY_PUSH:
        case REDIS_REPLY_ARRAY:
        case REDIS_REPLY_SET:
            value = rb_ary_new_capa(elements);
            break;
        case REDIS_REPLY_MAP:
            value = rb_hash_new_capa(elements / 2);
            break;
        default:
            rb_bug("[hiredis] Unexpected create array type %d", task->parent->type);
            break;
    }

    return reply_append(task, value);
}
static void *reply_create_integer(const redisReadTask *task, long long value) {
    return reply_append(task, LL2NUM(value));
}
static void *reply_create_double(const redisReadTask *task, double value, char *str, size_t len) {
    return reply_append(task, DBL2NUM(value));
}
static void *reply_create_nil(const redisReadTask *task) {
    return reply_append(task, Qnil);
}
static void *reply_create_bool(const redisReadTask *task, int bval) {
    reply_append(task, bval ? Qtrue : Qfalse);
    // Qfalse == NULL, so we can't return Qfalse as it would be interpreted as out of memory error.
    // So we return a token value instead and the caller is responsible for turning it into Qfalse.
    return (void*)(bval ? Qtrue : Redis_Qfalse);
}

static void reply_free(void *ptr) {
    // we let GC handle it.
}

/* Default set of functions to build the reply. Keep in mind that such a
 * function returning NULL is interpreted as OOM. */
static redisReplyObjectFunctions reply_functions = {
    reply_create_string,
    reply_create_array,
    reply_create_integer,
    reply_create_double,
    reply_create_nil,
    reply_create_bool,
    reply_free,
};

typedef struct {
    redisContext *context;
    int return_value;
} hiredis_buffer_read_args_t;

static void *hiredis_buffer_read_safe(void *_args) {
    hiredis_buffer_read_args_t *args = _args;
    args->return_value = redisBufferRead(args->context);
    return NULL;
}
static int hiredis_buffer_read_nogvl(redisContext *context) {
    hiredis_buffer_read_args_t args = {
        .context = context,
    };
    rb_thread_call_without_gvl(hiredis_buffer_read_safe, &args, RUBY_UBF_IO, 0);
    return args.return_value;
}

typedef struct {
    redisContext *context;
    int *done;
    int return_value;
} hiredis_buffer_write_args_t;

static void *hiredis_buffer_write_safe(void *_args) {
    hiredis_buffer_write_args_t *args = _args;
    args->return_value = redisBufferWrite(args->context, args->done);
    return NULL;
}
static int hiredis_buffer_write_nogvl(redisContext *context, int *done) {
    hiredis_buffer_write_args_t args = {
        .context = context,
        .done = done,
    };
    rb_thread_call_without_gvl(hiredis_buffer_write_safe, &args, RUBY_UBF_IO, 0);
    return args.return_value;
}

#define CONNECTION(from, name) \
    hiredis_connection_t *name = NULL; \
    TypedData_Get_Struct(from, hiredis_connection_t, &hiredis_connection_data_type, name); \
    if (name == NULL) { \
        rb_raise(rb_eArgError, "NULL found for " # name " when shouldn't be."); \
    }

typedef struct {
    redisContext *context;
    int return_value;
} hiredis_reconnect_args_t;

static void *hiredis_reconnect_safe(void *_args) {
    hiredis_reconnect_args_t *args = _args;
    args->return_value = redisReconnect(args->context);
    return NULL;
}

static int hiredis_reconnect_nogvl(redisContext *context) {
    hiredis_reconnect_args_t args = {
        .context = context,
        .return_value = 0
    };
    rb_thread_call_without_gvl(hiredis_reconnect_safe, &args, RUBY_UBF_IO, 0);
    return args.return_value;
}

static void *hiredis_connect_with_options_safe(void *options) {
    return (void *)redisConnectWithOptions(options);
}

static redisContext *hiredis_connect_with_options_nogvl(redisOptions *options) {
    return (redisContext *)rb_thread_call_without_gvl(hiredis_connect_with_options_safe, options, RUBY_UBF_IO, 0);
}

typedef struct {
    redisContext *context;
    struct timeval connect_timeout;
    struct timeval read_timeout;
    struct timeval write_timeout;
} hiredis_connection_t;

static void hiredis_connection_free(void *ptr) {
    hiredis_connection_t *connection = ptr;
    if (connection) {
         if (connection->context) {
           // redisFree may calls close() if we're still connected, but
           // it shoudln't be considered a "blocking" call given we don't
           // use any socket option that may make it a blocking operation.
           redisFree(connection->context);
         }
         xfree(connection);
    }
}

static size_t hiredis_connection_memsize(const void *ptr) {
    hiredis_connection_t *connection = (hiredis_connection_t *)ptr;

    size_t size = sizeof(hiredis_connection_t);

    if (connection->context) {
        size += sizeof(redisContext);
        if (connection->context->reader) {
            redisReader *reader = connection->context->reader;
            size += sizeof(redisReader);
            size += reader->maxbuf;
            size += reader->tasks * sizeof(redisReadTask);
        }
    }

    return size;
}

static const rb_data_type_t hiredis_connection_data_type = {
    .wrap_struct_name = "redis-client:hiredis_connection",
    .function = {
        .dmark = NULL,
        .dfree = hiredis_connection_free,
        .dsize = hiredis_connection_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY | RUBY_TYPED_WB_PROTECTED
};

static VALUE hiredis_alloc(VALUE klass) {
    hiredis_connection_t *connection;
    return TypedData_Make_Struct(klass, hiredis_connection_t, &hiredis_connection_data_type, connection);
}

static void redis_set_io_error(redisContext *context, int err) {
    if (err) {
        errno = err;
    }
    context->err = REDIS_ERR_IO;
    (void)!strerror_r(errno, context->errstr, sizeof(context->errstr));
}

static inline void redis_raise_error_and_disconnect(redisContext *context, VALUE timeout_error) {
    if (!context) return;

    int err = context->err;
    char errstr[128];
    if (context->err) {
      strncpy(errstr, context->errstr, 128);
    }
    redisNetClose(context);

    if (!err) {
        rb_raise(timeout_error, "Unknown Error (redis_raise_error_and_disconnect)");
    }

    // OpenSSL bug: The SSL_ERROR_SYSCALL with errno value of 0 indicates unexpected EOF from the peer.
    if (errno == EAGAIN || (err == REDIS_ERR_IO && errno == 0)) {
        errno = 0;
        rb_raise(timeout_error, "Resource temporarily unavailable");
    }

    switch(err) {
    case REDIS_ERR_IO:
        rb_sys_fail(0);
        break;
    case REDIS_ERR_PROTOCOL:
        rb_raise(rb_eRedisClientProtocolError, "%s", errstr);
    default:
        /* Raise something else */
        rb_raise(rb_eRedisClientConnectionError, "%s", errstr);
    }
}

static inline void hiredis_raise_error_and_disconnect(hiredis_connection_t *connection, VALUE timeout_error) {
    redisContext *context = connection->context;
    if (!context) return;
    connection->context = NULL;
    redis_raise_error_and_disconnect(context, timeout_error);
}

static VALUE hiredis_set_connect_timeout(VALUE self, VALUE timeout_us) {
    CONNECTION(self, connection);
    connection->connect_timeout.tv_sec = NUM2INT(timeout_us) / 1000000;
    connection->connect_timeout.tv_usec = NUM2INT(timeout_us) % 1000000;
    return timeout_us;
}

static VALUE hiredis_set_read_timeout(VALUE self, VALUE timeout_us) {
    CONNECTION(self, connection);
    connection->read_timeout.tv_sec = NUM2INT(timeout_us) / 1000000;
    connection->read_timeout.tv_usec = NUM2INT(timeout_us) % 1000000;
    return timeout_us;
}

static VALUE hiredis_set_write_timeout(VALUE self, VALUE timeout_us) {
    CONNECTION(self, connection);
    connection->write_timeout.tv_sec = NUM2INT(timeout_us) / 1000000;
    connection->write_timeout.tv_usec = NUM2INT(timeout_us) % 1000000;
    return timeout_us;
}

static int hiredis_wait_readable(int fd, const struct timeval *timeout, int *isset) {
    struct timeval to;
    struct timeval *toptr = NULL;

    rb_fdset_t fds;

    /* Be cautious: a call to rb_fd_init to initialize the rb_fdset_t structure
     * must be paired with a call to rb_fd_term to free it. */
    rb_fd_init(&fds);
    rb_fd_set(fd, &fds);

    /* rb_thread_{fd_,}select modifies the passed timeval, so we pass a copy */
    if (timeout != NULL && (timeout->tv_sec || timeout->tv_usec)) {
        memcpy(&to, timeout, sizeof(to));
        toptr = &to;
    }

    if (rb_thread_fd_select(fd + 1, &fds, NULL, NULL, toptr) < 0) {
        rb_fd_term(&fds);
        return -1;
    }

    if (rb_fd_isset(fd, &fds) && isset) {
        *isset = 1;
    }

    rb_fd_term(&fds);
    return 0;
}

struct fd_select {
    rb_fdset_t *write_fds;
    struct timeval *timeout;
    int max;
    int return_value;
};

static VALUE protected_writable_select(VALUE _args) {
    struct fd_select *args = (struct fd_select *)_args;
    args->return_value = rb_thread_fd_select(args->max, NULL, args->write_fds, NULL, args->timeout);
    return Qnil;
}

static int hiredis_wait_writable(int fd, const struct timeval *timeout, int *isset) {
    struct timeval to;
    struct timeval *toptr = NULL;

    /* Be cautious: a call to rb_fd_init to initialize the rb_fdset_t structure
     * must be paired with a call to rb_fd_term to free it. */
    rb_fdset_t fds;
    rb_fd_init(&fds);
    rb_fd_set(fd, &fds);

    /* rb_thread_{fd_,}select modifies the passed timeval, so we pass a copy */
    if (timeout != NULL && (timeout->tv_sec || timeout->tv_usec)) {
        memcpy(&to, timeout, sizeof(to));
        toptr = &to;
    }

    struct fd_select args = {
        .max = fd + 1,
        .write_fds = &fds,
        .timeout = toptr,
    };
    int status;

    (void)rb_protect(protected_writable_select, (VALUE)&args, &status);

    // Error in case an exception arrives in rb_thread_fd_select()
    // (e.g. from Thread.raise)
    if (status || args.return_value < 0) {
        rb_fd_term(&fds);
        return -1;
    }

    if (rb_fd_isset(fd, &fds) && isset) {
        *isset = 1;
    }

    rb_fd_term(&fds);
    return 0;
}

static VALUE hiredis_connect_finish(hiredis_connection_t *connection, redisContext *context) {
    if (connection->context && connection->context != context) {
        redisFree(context);
        rb_raise(rb_eRuntimeError, "HiredisConnection is already connected, must be a bug");
    }

    if (context->err) {
        redis_raise_error_and_disconnect(context, rb_eRedisClientCannotConnectError);
    }

    int writable = 0;
    int optval = 0;
    errno = 0;
    socklen_t optlen = sizeof(optval);

    /* Wait for socket to become writable */
    if (hiredis_wait_writable(context->fd, &connection->connect_timeout, &writable) < 0) {
        redis_set_io_error(context, ETIMEDOUT);
        redis_raise_error_and_disconnect(context, rb_eRedisClientCannotConnectError);
    }

    if (!writable) {
        redis_set_io_error(context, ETIMEDOUT);
        redis_raise_error_and_disconnect(context, rb_eRedisClientCannotConnectError);
    }

    /* Check for socket error */
    if (getsockopt(context->fd, SOL_SOCKET, SO_ERROR, &optval, &optlen) < 0) {
        redis_set_io_error(context, 0);
        redis_raise_error_and_disconnect(context, rb_eRedisClientCannotConnectError);
    }

    if (optval) {
        redis_set_io_error(context, optval);
        redis_raise_error_and_disconnect(context, rb_eRedisClientCannotConnectError);
    }

    context->reader->fn = &reply_functions;
    redisSetPushCallback(context, NULL);
    connection->context = context;
    return Qtrue;
}

static void hiredis_init_ssl(hiredis_connection_t *connection, VALUE ssl_param) {
    SSL_CONTEXT(ssl_param, ssl_context)

    if (redisInitiateSSLWithContext(connection->context, ssl_context->context) != REDIS_OK) {
        hiredis_raise_error_and_disconnect(connection, rb_eRedisClientCannotConnectError);
    }

    redisSSL *redis_ssl = redisGetSSLSocket(connection->context);

    if (redis_ssl->wantRead) {
        int readable = 0;
        if (hiredis_wait_readable(connection->context->fd, &connection->connect_timeout, &readable) < 0) {
            hiredis_raise_error_and_disconnect(connection, rb_eRedisClientCannotConnectError);
        }
        if (!readable) {
            errno = EAGAIN;
            redis_set_error(connection->context, REDIS_ERR_IO, "SSL Connection Timeout");
            hiredis_raise_error_and_disconnect(connection, rb_eRedisClientReadTimeoutError);
        }

        if (redisInitiateSSLContinue(connection->context) != REDIS_OK) {
            hiredis_raise_error_and_disconnect(connection, rb_eRedisClientCannotConnectError);
        };
    }
}

static VALUE hiredis_connect(VALUE self, VALUE path, VALUE host, VALUE port, VALUE ssl_param) {
    CONNECTION(self, connection);
    if (connection->context) {
        rb_raise(rb_eRuntimeError, "HiredisConnection is already connected, must be a bug");
    }

    redisOptions options = {
        .connect_timeout = &connection->connect_timeout,
        .options = REDIS_OPT_NONBLOCK
    };
    if (RTEST(path)) {
        REDIS_OPTIONS_SET_UNIX(&options, StringValuePtr(path));
    } else {
        REDIS_OPTIONS_SET_TCP(&options, StringValuePtr(host), NUM2INT(port));
    }

    redisContext *context = hiredis_connect_with_options_nogvl(&options);
    if (context && !RTEST(path)) {
        redisEnableKeepAlive(context);
    }

    VALUE success = hiredis_connect_finish(connection, context);

    if (RTEST(success) && !NIL_P(ssl_param)) {
        hiredis_init_ssl(connection, ssl_param);
    }

    return success;
}

static VALUE hiredis_reconnect(VALUE self, VALUE is_unix, VALUE ssl_param) {
    CONNECTION(self, connection);
    if (!connection->context) {
        return Qfalse;
    }

    // Clear context on the connection, since the nogvl call can raise an
    // exception after the redisReconnect() call succeeds and leave the
    // connection in a half-initialized state.
    redisContext *context = connection->context;
    connection->context = NULL;
    hiredis_reconnect_nogvl(context);

    VALUE success = hiredis_connect_finish(connection, context);

    if (RTEST(success)) {
        if (!RTEST(is_unix)) {
            redisEnableKeepAlive(connection->context);
        }

        if (RTEST(ssl_param)) {
            hiredis_init_ssl(connection, ssl_param);
        }
    }

    return success;
}

static VALUE hiredis_connected_p(VALUE self) {
    CONNECTION(self, connection);

    if (!connection->context) {
        return Qfalse;
    }

    if (connection->context->fd == REDIS_INVALID_FD) {
        return Qfalse;
    }

    return Qtrue;
}

static VALUE hiredis_write(VALUE self, VALUE command) {
    Check_Type(command, T_ARRAY);

    CONNECTION(self, connection);
    ENSURE_CONNECTED(connection);

    int size = (int)RARRAY_LEN(command);
    VALUE _argv_handle;
    char **argv = RB_ALLOCV_N(char *, _argv_handle, size);

    VALUE _argv_len_handle;
    size_t *argv_len = RB_ALLOCV_N(size_t, _argv_len_handle, size);

    for (int index = 0; index < size; index++) {
        VALUE arg = rb_ary_entry(command, index);
        Check_Type(arg, T_STRING);
        argv[index] = RSTRING_PTR(arg);
        argv_len[index] = RSTRING_LEN(arg);
    }

    redisAppendCommandArgv(connection->context, size, (const char **)argv, argv_len);
    return Qnil;
}

static VALUE hiredis_flush(VALUE self) {
    CONNECTION(self, connection);
    ENSURE_CONNECTED(connection);

    int wdone = 0;
    while (!wdone) {
        errno = 0;
        if (hiredis_buffer_write_nogvl(connection->context, &wdone) == REDIS_ERR) {
            if (errno == EAGAIN) {
                int writable = 0;

                if (hiredis_wait_writable(connection->context->fd, &connection->write_timeout, &writable) < 0) {
                    hiredis_raise_error_and_disconnect(connection, rb_eRedisClientWriteTimeoutError);
                }

                if (!writable) {
                    errno = EAGAIN;
                    hiredis_raise_error_and_disconnect(connection, rb_eRedisClientWriteTimeoutError);
                }
            } else {
                hiredis_raise_error_and_disconnect(connection, rb_eRedisClientWriteTimeoutError);
            }
        }
    }

    return Qtrue;
}


#define HIREDIS_FATAL_CONNECTION_ERROR -1
#define HIREDIS_CLIENT_TIMEOUT -2

static int hiredis_read_internal(hiredis_connection_t *connection, VALUE *reply) {
    void *redis_reply = NULL;
    int wdone = 0;

    // This struct being on the stack, the GC won't move nor collect that `stack` RArray.
    // We use that to avoid having to have a `mark` function with write barriers.
    // Not that it would be too hard, but if we mark the response objects, we'll likely end up
    // promoting them to the old generation which isn't desirable.
    VALUE stack = rb_ary_new();
    hiredis_reader_state_t reader_state = {
        .stack = stack,
        .task_index = &connection->context->reader->ridx,
    };
    connection->context->reader->privdata = &reader_state;

    /* Try to read pending replies */
    if (redisGetReplyFromReader(connection->context, &redis_reply) == REDIS_ERR) {
        return HIREDIS_FATAL_CONNECTION_ERROR; // Protocol error
    }

    if (redis_reply == NULL) {
        /* Write until the write buffer is drained */
        while (!wdone) {
            errno = 0;

            if (hiredis_buffer_write_nogvl(connection->context, &wdone) == REDIS_ERR) {
                return HIREDIS_FATAL_CONNECTION_ERROR; // Socket error
            }

            if (errno == EAGAIN) {
                int writable = 0;

                if (hiredis_wait_writable(connection->context->fd, &connection->write_timeout, &writable) < 0) {
                    return HIREDIS_CLIENT_TIMEOUT;
                }

                if (!writable) {
                    errno = EAGAIN;
                    return HIREDIS_CLIENT_TIMEOUT;
                }
            }
        }

        /* Read until there is a full reply */
        while (redis_reply == NULL) {
            errno = 0;

            if (hiredis_buffer_read_nogvl(connection->context) == REDIS_ERR) {
                return HIREDIS_FATAL_CONNECTION_ERROR; // Socket error
            }

            if (errno == EAGAIN) {
                int readable = 0;

                if (hiredis_wait_readable(connection->context->fd, &connection->read_timeout, &readable) < 0) {
                    return HIREDIS_CLIENT_TIMEOUT;
                }

                if (!readable) {
                    errno = EAGAIN;
                    return HIREDIS_CLIENT_TIMEOUT;
                }

                /* Retry */
                continue;
            }

            if (redisGetReplyFromReader(connection->context, &redis_reply) == REDIS_ERR) {
                return HIREDIS_FATAL_CONNECTION_ERROR; // Protocol error
            }
        }
    }

    /* Set reply object */
    if (reply != NULL) {
        *reply = rb_ary_entry(stack, 0);
    }

    RB_GC_GUARD(stack);

    return 0;
}

static VALUE hiredis_read(VALUE self) {
    CONNECTION(self, connection);
    ENSURE_CONNECTED(connection);

    VALUE reply = Qnil;
    switch (hiredis_read_internal(connection, &reply)) {
        case HIREDIS_FATAL_CONNECTION_ERROR:
            // The error is unrecoverable, we eagerly close the connection to ensure
            // it won't be re-used.
            hiredis_raise_error_and_disconnect(connection, rb_eRedisClientReadTimeoutError);
            break;
        case HIREDIS_CLIENT_TIMEOUT:
            // The timeout might have been expected (e.g. `PubSub#next_event`).
            // we let the caller decide if the connection should be closed.
            rb_raise(rb_eRedisClientReadTimeoutError, "Unknown Error (hiredis_read)");
            break;
    }

    if (reply == Redis_Qfalse) {
        // See reply_create_bool
        reply = Qfalse;
    }
    RB_GC_GUARD(self);
    return reply;
}

static VALUE hiredis_close(VALUE self) {
    CONNECTION(self, connection);
    if (connection->context) {
        redisNetClose(connection->context);
    }
    return Qnil;
}

static inline double diff_timespec_ms(const struct timespec *time1, const struct timespec *time0) {
  return ((time1->tv_sec - time0->tv_sec) * 1000.0)
      + (time1->tv_nsec - time0->tv_nsec) / 1000000.0;
}

static inline int timeval_to_msec(struct timeval duration) {
    return (int)(duration.tv_sec * 1000 + duration.tv_usec / 1000);
}

typedef struct {
    hiredis_connection_t *connection;
    struct timespec start;
    struct timespec end;
    int return_value;
} hiredis_measure_round_trip_delay_args_t;

static const size_t pong_length = 7;

static void *hiredis_measure_round_trip_delay_safe(void *_args) {
    hiredis_measure_round_trip_delay_args_t *args = _args;
    hiredis_connection_t *connection = args->connection;
    redisReader *reader = connection->context->reader;

    if (reader->len - reader->pos != 0) {
        args->return_value = REDIS_ERR;
        return NULL;
    }

    redisAppendFormattedCommand(connection->context, "PING\r\n", 6);

    clock_gettime(CLOCK_MONOTONIC, &args->start);

    int wdone = 0;
    do {
        if (redisBufferWrite(connection->context, &wdone) == REDIS_ERR) {
            args->return_value = REDIS_ERR;
            return NULL;
        }
    } while (!wdone);

    struct pollfd   wfd[1];
    wfd[0].fd     = connection->context->fd;
    wfd[0].events = POLLIN;
    int retval = poll(wfd, 1, timeval_to_msec(connection->read_timeout));
    if (retval == -1) {
        args->return_value = REDIS_ERR_IO;
        return NULL;
    } else if (!retval) {
        args->return_value = REDIS_ERR_IO;
        return NULL;
    }

    redisBufferRead(connection->context);

    if (reader->len - reader->pos != pong_length) {
        args->return_value = REDIS_ERR;
        return NULL;
    }

    if (strncmp(reader->buf + reader->pos, "+PONG\r\n", pong_length) != 0) {
        args->return_value = REDIS_ERR;
        return NULL;
    }
    reader->pos += pong_length;

    clock_gettime(CLOCK_MONOTONIC, &args->end);
    args->return_value = REDIS_OK;
    return NULL;
}

static VALUE hiredis_measure_round_trip_delay(VALUE self) {
    CONNECTION(self, connection);
    ENSURE_CONNECTED(connection);

    hiredis_measure_round_trip_delay_args_t args = {
        .connection = connection,
    };
    rb_thread_call_without_gvl(hiredis_measure_round_trip_delay_safe, &args, RUBY_UBF_IO, 0);

    if (args.return_value != REDIS_OK) {
        hiredis_raise_error_and_disconnect(connection, rb_eRedisClientReadTimeoutError);
        return Qnil; // unreachable;
    }

    return DBL2NUM(diff_timespec_ms(&args.end, &args.start));
}

RUBY_FUNC_EXPORTED void Init_hiredis_connection(void) {
    // Qfalse == NULL, so we can't return Qfalse in `reply_create_bool()`
    RUBY_ASSERT((void *)Qfalse == NULL);
    RUBY_ASSERT((void *)Qnil != NULL);

    redisInitOpenSSL();

    id_parse = rb_intern("parse");
    rb_global_variable(&Redis_Qfalse);
    Redis_Qfalse = rb_obj_alloc(rb_cObject);

    VALUE rb_cRedisClient = rb_const_get(rb_cObject, rb_intern("RedisClient"));

    rb_eRedisClientCommandError = rb_const_get(rb_cRedisClient, rb_intern("CommandError"));
    rb_global_variable(&rb_eRedisClientCommandError);

    rb_eRedisClientConnectionError = rb_const_get(rb_cRedisClient, rb_intern("ConnectionError"));
    rb_global_variable(&rb_eRedisClientConnectionError);

    rb_eRedisClientCannotConnectError = rb_const_get(rb_cRedisClient, rb_intern("CannotConnectError"));
    rb_global_variable(&rb_eRedisClientCannotConnectError);

    rb_eRedisClientProtocolError = rb_const_get(rb_cRedisClient, rb_intern("ProtocolError"));
    rb_global_variable(&rb_eRedisClientProtocolError);

    rb_eRedisClientReadTimeoutError = rb_const_get(rb_cRedisClient, rb_intern("ReadTimeoutError"));
    rb_global_variable(&rb_eRedisClientReadTimeoutError);

    rb_eRedisClientWriteTimeoutError = rb_const_get(rb_cRedisClient, rb_intern("WriteTimeoutError"));
    rb_global_variable(&rb_eRedisClientWriteTimeoutError);

    VALUE rb_cHiredisConnection = rb_define_class_under(rb_cRedisClient, "HiredisConnection", rb_cObject);
    rb_define_alloc_func(rb_cHiredisConnection, hiredis_alloc);

    rb_define_private_method(rb_cHiredisConnection, "connect_timeout_us=", hiredis_set_connect_timeout, 1);
    rb_define_private_method(rb_cHiredisConnection, "read_timeout_us=", hiredis_set_read_timeout, 1);
    rb_define_private_method(rb_cHiredisConnection, "write_timeout_us=", hiredis_set_write_timeout, 1);

    rb_define_private_method(rb_cHiredisConnection, "_connect", hiredis_connect, 4);
    rb_define_private_method(rb_cHiredisConnection, "_reconnect", hiredis_reconnect, 2);
    rb_define_method(rb_cHiredisConnection, "connected?", hiredis_connected_p, 0);

    rb_define_private_method(rb_cHiredisConnection, "_write", hiredis_write, 1);
    rb_define_private_method(rb_cHiredisConnection, "_read", hiredis_read, 0);
    rb_define_private_method(rb_cHiredisConnection, "flush", hiredis_flush, 0);
    rb_define_private_method(rb_cHiredisConnection, "_close", hiredis_close, 0);
    rb_define_method(rb_cHiredisConnection, "measure_round_trip_delay", hiredis_measure_round_trip_delay, 0);

    VALUE rb_cHiredisSSLContext = rb_define_class_under(rb_cHiredisConnection, "SSLContext", rb_cObject);
    rb_define_alloc_func(rb_cHiredisSSLContext, hiredis_ssl_context_alloc);
    rb_define_private_method(rb_cHiredisSSLContext, "init", hiredis_ssl_context_init, 5);
}
