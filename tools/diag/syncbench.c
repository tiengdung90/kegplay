/* Đo + kiểm đúng các nguyên hàm đồng bộ của Windows dưới Wine (dùng để so msync bật/tắt).
 * Biên dịch: x86_64-w64-mingw32-gcc -O2 -o syncbench.exe syncbench.c
 * In: số thao tác/giây cho 4 bài; trả mã 1 nếu kết quả sai (đếm lệch, chờ hết hạn bất thường). */
#include <windows.h>
#include <stdio.h>

#define N 200000
static HANDLE ev_a, ev_b, mtx, sem, done;
static volatile LONG counter;

static double now(void) { LARGE_INTEGER f, c; QueryPerformanceFrequency(&f); QueryPerformanceCounter(&c); return (double)c.QuadPart / f.QuadPart; }

static DWORD WINAPI pong(void *p) { for (int i = 0; i < N; i++) { WaitForSingleObject(ev_a, INFINITE); SetEvent(ev_b); } return 0; }
static DWORD WINAPI mutex_worker(void *p) { for (int i = 0; i < N / 4; i++) { WaitForSingleObject(mtx, INFINITE); counter++; ReleaseMutex(mtx); } return 0; }
static DWORD WINAPI sem_consumer(void *p) { for (int i = 0; i < N; i++) WaitForSingleObject(sem, INFINITE); SetEvent(done); return 0; }

int main(void)
{
    int bad = 0; double t; HANDLE th[4];
    /* 1. bóng bàn giữa 2 luồng bằng 2 event tự reset: đo độ trễ đánh thức */
    ev_a = CreateEventW(NULL, FALSE, FALSE, NULL); ev_b = CreateEventW(NULL, FALSE, FALSE, NULL);
    th[0] = CreateThread(NULL, 0, pong, NULL, 0, NULL);
    t = now();
    for (int i = 0; i < N; i++) { SetEvent(ev_a); if (WaitForSingleObject(ev_b, 5000) != WAIT_OBJECT_0) { bad = 1; break; } }
    printf("event ping-pong : %8.0f vong/giay\n", N / (now() - t));
    WaitForSingleObject(th[0], INFINITE);
    /* 2. 4 luồng tranh 1 mutex: đếm phải đúng */
    mtx = CreateMutexW(NULL, FALSE, NULL); counter = 0; t = now();
    for (int i = 0; i < 4; i++) th[i] = CreateThread(NULL, 0, mutex_worker, NULL, 0, NULL);
    WaitForMultipleObjects(4, th, TRUE, INFINITE);
    printf("mutex 4 luong   : %8.0f lan/giay  (dem %ld, dung %d)\n", N / (now() - t), counter, N / 4 * 4);
    if (counter != N / 4 * 4) bad = 1;
    /* 3. semaphore sản xuất/tiêu thụ */
    sem = CreateSemaphoreW(NULL, 0, N, NULL); done = CreateEventW(NULL, TRUE, FALSE, NULL); t = now();
    th[0] = CreateThread(NULL, 0, sem_consumer, NULL, 0, NULL);
    for (int i = 0; i < N; i++) ReleaseSemaphore(sem, 1, NULL);
    if (WaitForSingleObject(done, 20000) != WAIT_OBJECT_0) bad = 1;
    printf("semaphore       : %8.0f lan/giay\n", N / (now() - t));
    /* 4. chờ nhiều đối tượng + hết hạn */
    HANDLE evs[8]; for (int i = 0; i < 8; i++) evs[i] = CreateEventW(NULL, TRUE, FALSE, NULL);
    SetEvent(evs[5]);
    if (WaitForMultipleObjects(8, evs, FALSE, 0) != WAIT_OBJECT_0 + 5) bad = 1;
    if (WaitForMultipleObjects(8, evs, TRUE, 50) != WAIT_TIMEOUT) bad = 1;
    for (int i = 0; i < 8; i++) SetEvent(evs[i]);
    if (WaitForMultipleObjects(8, evs, TRUE, 0) != WAIT_OBJECT_0) bad = 1;
    printf("ket qua         : %s\n", bad ? "SAI" : "dung");
    return bad;
}
