/*
 * wbfagentd — root helper for WFBAgent
 * Listens on 127.0.0.1:39393 only.
 *
 *   client -> "EXEC\n"  + command bytes, then shutdown(WR)
 *   daemon -> runs /bin/sh -c <command>, streams stdout+stderr back, closes
 *
 *   client -> "SHELL\n"
 *   daemon -> attaches the socket to a root pty running /bin/sh -i
 *
 *   client -> "PING\n"
 *   daemon -> "PONG\n"
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/select.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <termios.h>

#define WBF_PORT 39393
#define WBF_MAXCMD (256 * 1024)

static void write_all(int fd, const char *buf, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = write(fd, buf + sent, len - sent);
        if (n <= 0) {
            if (n < 0 && errno == EINTR) continue;
            return;
        }
        sent += (size_t)n;
    }
}

static void bridge(int a, int b) {
    char buf[4096];
    for (;;) {
        fd_set rf;
        FD_ZERO(&rf);
        FD_SET(a, &rf);
        FD_SET(b, &rf);
        int maxfd = (a > b ? a : b) + 1;
        int r = select(maxfd, &rf, NULL, NULL, NULL);
        if (r <= 0) {
            if (r < 0 && errno == EINTR) continue;
            return;
        }
        if (FD_ISSET(a, &rf)) {
            ssize_t n = read(a, buf, sizeof(buf));
            if (n <= 0) return;
            write_all(b, buf, (size_t)n);
        }
        if (FD_ISSET(b, &rf)) {
            ssize_t n = read(b, buf, sizeof(buf));
            if (n <= 0) return;
            write_all(a, buf, (size_t)n);
        }
    }
}

static void handle_shell(int c) {
    int master = posix_openpt(O_RDWR | O_NOCTTY);
    if (master < 0) {
        write_all(c, "ERR no-pty\n", 11);
        return;
    }
    if (grantpt(master) != 0 || unlockpt(master) != 0) {
        write_all(c, "ERR pty-unlock\n", 15);
        close(master);
        return;
    }
    const char *slave_name = ptsname(master);
    if (!slave_name) {
        write_all(c, "ERR pty-name\n", 13);
        close(master);
        return;
    }

    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        int slave = open(slave_name, O_RDWR);
        if (slave < 0) _exit(1);
        ioctl(slave, TIOCSCTTY, 0);
        dup2(slave, STDIN_FILENO);
        dup2(slave, STDOUT_FILENO);
        dup2(slave, STDERR_FILENO);
        if (slave > 2) close(slave);
        close(master);
        setenv("TERM", "xterm-256color", 1);
        setenv("HOME", "/var/root", 1);
        setenv("PATH", "/var/jb/usr/bin:/var/jb/usr/sbin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin", 1);
        execl("/bin/sh", "sh", "-i", (char *)NULL);
        execl("/var/jb/usr/bin/sh", "sh", "-i", (char *)NULL);
        _exit(1);
    }
    if (pid < 0) {
        write_all(c, "ERR fork\n", 9);
        close(master);
        return;
    }
    bridge(master, c);
    close(master);
    kill(pid, SIGHUP);
    int st = 0;
    waitpid(pid, &st, WNOHANG);
    write_all(c, "\n[shell exited]\n", 16);
}

static void handle_exec(int c, char *cmd) {
    int fds[2];
    if (pipe(fds) != 0) {
        write_all(c, "ERR pipe\n", 9);
        return;
    }
    pid_t pid = fork();
    if (pid == 0) {
        close(fds[0]);
        dup2(fds[1], STDOUT_FILENO);
        dup2(fds[1], STDERR_FILENO);
        if (fds[1] > 2) close(fds[1]);
        chdir("/");
        setenv("PATH", "/var/jb/usr/bin:/var/jb/usr/sbin:/usr/bin:/bin:/usr/sbin:/sbin", 1);
        execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }
    close(fds[1]);
    if (pid < 0) {
        write_all(c, "ERR fork\n", 9);
        close(fds[0]);
        return;
    }
    char buf[8192];
    for (;;) {
        ssize_t n = read(fds[0], buf, sizeof(buf));
        if (n <= 0) break;
        write_all(c, buf, (size_t)n);
    }
    close(fds[0]);
    int st = 0;
    waitpid(pid, &st, 0);
}

static void handle_client(int c) {
    char hdr[16];
    size_t hl = 0;
    while (hl < sizeof(hdr) - 1) {
        ssize_t n = read(c, hdr + hl, 1);
        if (n <= 0) { close(c); return; }
        if (hdr[hl] == '\n') { hdr[hl] = 0; break; }
        hl++;
    }
    hdr[sizeof(hdr) - 1] = 0;

    if (strncmp(hdr, "SHELL", 5) == 0) {
        handle_shell(c);
    } else if (strncmp(hdr, "PING", 4) == 0) {
        write_all(c, "PONG\n", 5);
    } else if (strncmp(hdr, "EXEC", 4) == 0) {
        char *cmd = malloc(WBF_MAXCMD);
        if (!cmd) { close(c); return; }
        size_t total = 0;
        for (;;) {
            if (total >= WBF_MAXCMD - 1) break;
            ssize_t n = read(c, cmd + total, WBF_MAXCMD - 1 - total);
            if (n <= 0) break;
            total += (size_t)n;
        }
        cmd[total] = 0;
        handle_exec(c, cmd);
        free(cmd);
    }
    close(c);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    signal(SIGHUP, SIG_IGN);

    int srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) return 1;
    int one = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(WBF_PORT);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(srv, (struct sockaddr *)&a, sizeof(a)) != 0) return 2;
    if (listen(srv, 16) != 0) return 3;

    for (;;) {
        int c = accept(srv, NULL, NULL);
        if (c < 0) {
            if (errno == EINTR) continue;
            usleep(100000);
            continue;
        }
        pid_t pid = fork();
        if (pid == 0) {
            close(srv);
            handle_client(c);
            _exit(0);
        }
        close(c);
        if (pid < 0) continue;
        int st = 0;
        waitpid(pid, &st, WNOHANG);
    }
    return 0;
}
