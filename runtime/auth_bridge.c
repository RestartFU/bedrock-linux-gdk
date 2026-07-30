#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{
    void *queue;
    void *context;
    void (CALLBACK *callback)(void *);
    unsigned char internal[sizeof(void *) * 4];
} XAsyncBlock;

typedef void (CALLBACK *RemoteShow)(
    void *context,
    uint32_t user_identifier,
    void *operation,
    const char *url,
    const char *code,
    size_t qr_code_size,
    const void *qr_code
);

typedef void (CALLBACK *RemoteClose)(
    void *context,
    uint32_t user_identifier,
    void *operation
);

typedef struct
{
    RemoteShow show;
    RemoteClose close;
    void *context;
} RemoteHandlers;

typedef HRESULT (WINAPI *InitializeApi)(ULONG, ULONG, CHAR, void *);
typedef HRESULT (WINAPI *QueryApi)(const GUID *, REFIID, void **);
typedef HRESULT (WINAPI *SetRemoteHandlers)(void *, void *, RemoteHandlers *);
typedef HRESULT (WINAPI *AddUserAsync)(void *, int, XAsyncBlock *);
typedef HRESULT (WINAPI *AddUserResult)(void *, XAsyncBlock *, void **);
typedef HRESULT (WINAPI *GetUserId)(void *, void *, uint64_t *);
typedef HRESULT (WINAPI *GetGamertag)(
    void *,
    void *,
    int,
    size_t,
    char *,
    size_t *
);
typedef ULONG (WINAPI *ReleaseInterface)(void *);
typedef HRESULT (WINAPI *RoInitializeFn)(int);
typedef void (WINAPI *RoUninitializeFn)(void);

static const GUID CLSID_XUserImpl =
    {0x01acd177, 0x91f9, 0x4763, {0xa3, 0x8e, 0xcc, 0xbb, 0x55, 0xce, 0x32, 0xe0}};
static const GUID IID_IXUserPlatform =
    {0x26f3c674, 0xa2fe, 0x44fa, {0xb6, 0xc4, 0xa3, 0x23, 0xbc, 0x94, 0xff, 0x53}};
static const GUID IID_IXUserGamertag =
    {0xcef4fac0, 0x7676, 0x4a94, {0xa1, 0x19, 0x4c, 0x43, 0xf9, 0xeb, 0x5b, 0x74}};

static void emit(const char *format, ...)
{
    const char *result_path = getenv("BEDROCK_LINUX_GDK_AUTH_RESULT");
    char line[1024];
    va_list arguments;
    FILE *result;

    va_start(arguments, format);
    vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);

    puts(line);
    fflush(stdout);
    if (!result_path || !result_path[0])
        return;

    result = fopen(result_path, "a");
    if (!result)
        return;
    fprintf(result, "%s\n", line);
    fclose(result);
}

static void print_error(const char *operation, HRESULT status)
{
    emit("error\t%s\t0x%08lx", operation, (unsigned long)status);
}

static void CALLBACK remote_show(
    void *context,
    uint32_t user_identifier,
    void *operation,
    const char *url,
    const char *code,
    size_t qr_code_size,
    const void *qr_code
)
{
    (void)context;
    (void)user_identifier;
    (void)operation;
    (void)qr_code_size;
    (void)qr_code;
    emit("device\t%s\t%s", url ? url : "", code ? code : "");
}

static void CALLBACK remote_close(
    void *context,
    uint32_t user_identifier,
    void *operation
)
{
    (void)context;
    (void)user_identifier;
    (void)operation;
    emit("device-closed");
}

static void CALLBACK add_user_complete(void *raw_async)
{
    XAsyncBlock *async = raw_async;
    SetEvent((HANDLE)async->context);
}

static void release_interface(void *interface)
{
    void **vtable;
    ReleaseInterface release;

    if (!interface)
        return;
    vtable = *(void ***)interface;
    release = (ReleaseInterface)vtable[2];
    release(interface);
}

int main(void)
{
    HMODULE combase;
    HMODULE runtime;
    RoInitializeFn ro_initialize;
    RoUninitializeFn ro_uninitialize;
    InitializeApi initialize;
    QueryApi query;
    void *users = NULL;
    void *gamertags = NULL;
    void *user = NULL;
    void **vtable;
    SetRemoteHandlers set_handlers;
    AddUserAsync add_async;
    AddUserResult add_result;
    GetUserId get_user_id;
    GetGamertag get_gamertag;
    RemoteHandlers handlers;
    XAsyncBlock async;
    HANDLE completed;
    HRESULT status;
    uint64_t user_id = 0;
    char gamertag[256] = {0};
    size_t used = 0;

    combase = LoadLibraryA("combase.dll");
    runtime = LoadLibraryA("xgameruntime.dll.threading");
    if (!runtime)
    {
        print_error("load-runtime", HRESULT_FROM_WIN32(GetLastError()));
        return 1;
    }

    ro_initialize = combase
        ? (RoInitializeFn)GetProcAddress(combase, "RoInitialize")
        : NULL;
    ro_uninitialize = combase
        ? (RoUninitializeFn)GetProcAddress(combase, "RoUninitialize")
        : NULL;
    if (ro_initialize)
        ro_initialize(1);

    initialize = (InitializeApi)GetProcAddress(runtime, "InitializeApiImplEx2");
    query = (QueryApi)GetProcAddress(runtime, "QueryApiImpl");
    if (!initialize || !query)
    {
        print_error("runtime-exports", E_NOINTERFACE);
        return 1;
    }

    status = initialize(10002, 7822, 0x0a, NULL);
    if (FAILED(status))
    {
        print_error("initialize", status);
        return 1;
    }

    status = query(&CLSID_XUserImpl, &IID_IXUserPlatform, &users);
    if (FAILED(status) || !users)
    {
        print_error("user-interface", status);
        return 1;
    }

    vtable = *(void ***)users;
    set_handlers = (SetRemoteHandlers)vtable[43];
    add_async = (AddUserAsync)vtable[7];
    add_result = (AddUserResult)vtable[8];
    get_user_id = (GetUserId)vtable[11];

    handlers.show = remote_show;
    handlers.close = remote_close;
    handlers.context = NULL;
    status = set_handlers(users, NULL, &handlers);
    if (FAILED(status))
    {
        print_error("remote-handlers", status);
        return 1;
    }

    completed = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (!completed)
    {
        print_error("completion-event", HRESULT_FROM_WIN32(GetLastError()));
        return 1;
    }

    memset(&async, 0, sizeof(async));
    async.context = completed;
    async.callback = add_user_complete;
    status = add_async(users, 4, &async);
    if (FAILED(status))
    {
        print_error("start-sign-in", status);
        return 1;
    }

    if (WaitForSingleObject(completed, 900000) != WAIT_OBJECT_0)
    {
        print_error("sign-in-timeout", HRESULT_FROM_WIN32(ERROR_TIMEOUT));
        return 1;
    }

    status = add_result(users, &async, &user);
    if (FAILED(status) || !user)
    {
        print_error("finish-sign-in", status);
        return 1;
    }

    status = get_user_id(users, user, &user_id);
    if (FAILED(status) || !user_id)
    {
        print_error("account-identity", FAILED(status) ? status : E_FAIL);
        return 1;
    }

    status = query(&CLSID_XUserImpl, &IID_IXUserGamertag, &gamertags);
    if (SUCCEEDED(status) && gamertags)
    {
        vtable = *(void ***)gamertags;
        get_gamertag = (GetGamertag)vtable[3];
        status = get_gamertag(
            gamertags,
            user,
            3,
            sizeof(gamertag),
            gamertag,
            &used
        );
        if (FAILED(status))
            gamertag[0] = '\0';
    }

    emit(
        "account\t%llu\t%s",
        (unsigned long long)user_id,
        gamertag
    );

    release_interface(gamertags);
    release_interface(users);
    CloseHandle(completed);
    if (ro_uninitialize)
        ro_uninitialize();
    FreeLibrary(runtime);
    if (combase)
        FreeLibrary(combase);
    return 0;
}
