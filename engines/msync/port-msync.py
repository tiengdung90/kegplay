#!/usr/bin/env python3
# Ghép msync (lấy từ mã nguồn CrossOver 26.3, Wine 11.0) vào cây mã Wine 11.18 của kegPlay.
#   python3 port-msync.py <engines/msync/src (file lấy từ CrossOver)> <cây Wine 11.18 cần vá>
# CrossOver gắn msync làm "phần phụ trợ" của khung đồng bộ trong tiến trình (inproc_sync) — đúng khung Wine 11.18 có sẵn
# cho ntsync của Linux. Script chép 4 file msync.{c,h} rồi nối ~10 điểm; mỗi điểm kiểm đúng đoạn gốc, lệch là dừng.
import sys, re, shutil, os
cx, w = sys.argv[1], sys.argv[2]
def rd(p): return open(os.path.join(w, p), encoding='utf-8').read()
def wr(p, s): open(os.path.join(w, p), 'w', encoding='utf-8').write(s)
def sub(p, old, new, count=1):
    s = rd(p)
    if new in s: return
    if s.count(old) != 1: sys.exit(f"LỖI {p}: đoạn gốc xuất hiện {s.count(old)} lần:\n{old[:200]}")
    wr(p, s.replace(old, new, count))

for p in ('dlls/ntdll/unix/msync.c', 'dlls/ntdll/unix/msync.h', 'server/msync.c', 'server/msync.h'):
    shutil.copy(os.path.join(cx, p), os.path.join(w, p))

# ---------- wineserver ----------
sub('server/Makefile.in', '\tmapping.c \\\n', '\tmapping.c \\\n\tmsync.c \\\n')
sub('server/main.c', '#include "unicode.h"\n', '#include "unicode.h"\n#include "msync.h"\n')
sub('server/main.c', '    sock_init();\n    open_master_socket();\n',
    '    sock_init();\n    msync_init_shm();\n    open_master_socket();\n    msync_init();\n')
sub('server/thread.c', '#include "request.h"\n', '#include "request.h"\n#include "msync.h"\n')
sub('server/thread.c',
    '    else\n    {\n        reply->handle = get_thread_id( current ) | 1; /* arbitrary token */\n        send_client_fd( current->process, fd, reply->handle );\n',
    '    else\n    {\n        if (do_msync())\n        {\n            reply->handle = (unsigned int)fd;\n            return;\n        }\n\n'
    '        reply->handle = get_thread_id( current ) | 1; /* arbitrary token */\n        send_client_fd( current->process, fd, reply->handle );\n')
sub('server/inproc_sync.c', '#include "user.h"\n', '#include "user.h"\n#include "msync.h"\n')
cxs = open(os.path.join(cx, 'server/inproc_sync.c'), encoding='utf-8').read()
a = cxs.index('#elif defined(__APPLE__)'); b = cxs.index('#else /* NTSYNC_IOC_EVENT_READ */', a)
block = cxs[a:b]
# CrossOver 11.0 dùng object_ops kiểu liệt kê vị trí; Wine 11.18 dùng kiểu đặt tên trường
block = re.sub(r'static const struct object_ops inproc_sync_ops =\n\{.*?\n\};',
    'static const struct object_ops inproc_sync_ops =\n{\n    .size    = sizeof(struct inproc_sync),\n    .type    = &no_type,\n'
    '    .dump    = inproc_sync_dump,\n    .signal  = inproc_sync_signal,\n    .destroy = inproc_sync_destroy,\n};', block, flags=re.S)
sub('server/inproc_sync.c', '#else /* NTSYNC_IOC_EVENT_READ */\n', block + '#else /* NTSYNC_IOC_EVENT_READ */\n')
sub('server/inproc_sync.c',
    '    if ((fd = get_obj_inproc_sync( obj, &reply->type )) < 0) set_error( STATUS_NOT_IMPLEMENTED );\n    else send_client_fd( current->process, fd, req->handle );\n',
    '    if ((fd = get_obj_inproc_sync( obj, &reply->type )) < 0) set_error( STATUS_NOT_IMPLEMENTED );\n    else\n    {\n'
    '        if (do_msync()) reply->shm_idx = (unsigned int)fd;\n        else send_client_fd( current->process, fd, req->handle );\n    }\n')
sub('server/protocol.def',
    '    int           type;         /* inproc sync type */\n    unsigned int access;        /* handle access rights */\n@END\n',
    '    int           type;         /* inproc sync type */\n    unsigned int access;        /* handle access rights */\n'
    '    unsigned int shm_idx;       /* optional for index-based sync implementations */\n@END\n')

# ---------- ntdll ----------
sub('dlls/ntdll/Makefile.in', '\tunix/loader.c \\\n', '\tunix/loader.c \\\n\tunix/msync.c \\\n')
sub('dlls/ntdll/unix/loader.c', '#include "unix_private.h"\n', '#include "unix_private.h"\n#include "msync.h"\n')
sub('dlls/ntdll/unix/loader.c', '    server_init_process( data );\n    virtual_map_user_shared_data();\n',
    '    server_init_process( data );\n    msync_init();\n    virtual_map_user_shared_data();\n')
sub('dlls/ntdll/unix/sync.c', '#include "unix_private.h"\n', '#include "unix_private.h"\n#include "msync.h"\n')
wrap = '''#elif defined(__APPLE__)

static NTSTATUS linux_release_semaphore_obj( int obj, ULONG count, ULONG *prev_count )
{
    return msync_release_semaphore_obj( obj, count, prev_count );
}

static NTSTATUS linux_query_semaphore_obj( int obj, SEMAPHORE_BASIC_INFORMATION *info )
{
    return msync_query_semaphore_obj( obj, info );
}

static NTSTATUS linux_set_event_obj( int obj, LONG *prev_state )
{
    return msync_set_event_obj( obj, prev_state );
}

static NTSTATUS linux_reset_event_obj( int obj, LONG *prev_state )
{
    return msync_reset_event_obj( obj, prev_state );
}

static NTSTATUS linux_pulse_event_obj( int obj, LONG *prev_state )
{
    return msync_pulse_event_obj( obj, prev_state );
}

static NTSTATUS linux_query_event_obj( int obj, EVENT_BASIC_INFORMATION *info )
{
    return msync_query_event_obj( obj, info );
}

static NTSTATUS linux_release_mutex_obj( int obj, LONG *prev_count )
{
    return msync_release_mutex_obj( obj, prev_count );
}

static NTSTATUS linux_query_mutex_obj( int obj, MUTANT_BASIC_INFORMATION *info )
{
    return msync_query_mutex_obj( obj, info );
}

/* Wine 11.18 truyền WAIT_TYPE; msync (CrossOver, Wine 11.0) nhận cờ wait_any */
static NTSTATUS linux_wait_objs( int device, DWORD count, const int *objs, WAIT_TYPE type,
                                 int alert_fd, const LARGE_INTEGER *timeout )
{
    return msync_wait_objs( count, objs, type != WaitAll, alert_fd, timeout );
}

#else /* NTSYNC_IOC_EVENT_READ */

static NTSTATUS linux_release_semaphore_obj('''
sub('dlls/ntdll/unix/sync.c', '#else /* NTSYNC_IOC_EVENT_READ */\n\nstatic NTSTATUS linux_release_semaphore_obj(', wrap)
sub('dlls/ntdll/unix/sync.c', '    assert( ref >= 0 );\n    if (!ref) close( fd );\n',
    '    assert( ref >= 0 );\n    if (!ref)\n    {\n        if (do_msync())\n            msync_close( fd );\n        else\n            close( fd );\n    }\n')
sub('dlls/ntdll/unix/sync.c',
    '            sync->fd = wine_server_receive_fd( &fd_handle );\n            assert( wine_server_ptr_handle(fd_handle) == handle );\n',
    '            if (do_msync())\n            {\n                sync->fd = reply->shm_idx;\n            }\n            else\n            {\n'
    '                sync->fd = wine_server_receive_fd( &fd_handle );\n                assert( wine_server_ptr_handle(fd_handle) == handle );\n            }\n')
sub('dlls/ntdll/unix/sync.c',
    '                data->alert_fd = fd = wine_server_receive_fd( &token );\n                assert( token == reply->handle );\n',
    '                if (do_msync())\n                {\n                    data->alert_fd = fd = reply->handle;\n                }\n                else\n                {\n'
    '                    data->alert_fd = fd = wine_server_receive_fd( &token );\n                    assert( token == reply->handle );\n                }\n')
print("port-msync: ok")
