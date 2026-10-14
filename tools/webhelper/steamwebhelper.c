/* Wrapper installed as steamwebhelper.exe. Steam's CEF 126 draws black windows under Wine on
 * macOS; running it with GPU off in a single process renders correctly. The real helper is kept
 * next to this one as steamwebhelper_real.exe. */
#include <windows.h>
#include <wchar.h>

int wmain(void)
{
    static const wchar_t extra[] = L" --disable-gpu --disable-gpu-compositing --single-process";
    static const wchar_t real[] = L"steamwebhelper_real.exe";
    wchar_t exe[MAX_PATH], *slash, *args = GetCommandLineW(), *cmd;
    STARTUPINFOW si = { sizeof(si) };
    PROCESS_INFORMATION pi;
    DWORD code = 1, n;
    size_t len;

    n = GetModuleFileNameW(NULL, exe, MAX_PATH);
    if (!n || n >= MAX_PATH) return 1;
    if (!(slash = wcsrchr(exe, L'\\'))) return 1;
    if ((size_t)(slash + 1 - exe) + wcslen(real) >= MAX_PATH) return 1;
    wcscpy(slash + 1, real);

    /* skip argv[0] */
    if (*args == L'"') { args = wcschr(args + 1, L'"'); args = args ? args + 1 : L""; }
    else while (*args && *args != L' ') args++;

    len = wcslen(exe) + wcslen(args) + wcslen(extra) + 4;
    if (!(cmd = HeapAlloc(GetProcessHeap(), 0, len * sizeof(wchar_t)))) return 1;
    /* wsprintfW truncates at 1024 characters; build the command line without it */
    cmd[0] = L'"';
    wcscpy(cmd + 1, exe);
    wcscat(cmd, L"\"");
    wcscat(cmd, args);
    /* renderer/gpu/utility children don't need the flags; only the browser process does */
    if (!wcsstr(args, L"--type=")) wcscat(cmd, extra);

    if (!CreateProcessW(exe, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) return 1;
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &code);
    return (int)code;
}
