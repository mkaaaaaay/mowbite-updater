# the test registry's front (test/run.sh): passes all on to the registry behind it. while the file "hold" names a
# repository, what the docker daemon downloads from it stops after the headers of the answer (a download that lasts as
# long as a case needs: the daemon gives up waiting for headers, not for a slow body; the updater's own questions with
# buildx get through). nothing gets through while the file "down" is there (a registry that doesn't answer).
# python3 gate.py <port> <the registry's port> <folder of the two files>
import os
import socket
import sys
import threading
import time

port, upstream, folder = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
hold, down = os.path.join(folder, 'hold'), os.path.join(folder, 'down')


def held(data):
    try:
        with open(hold) as f:
            repos = f.read().split()
    except OSError:
        return False
    # (the daemon says it's docker/<version>, buildx asks as containerd)
    head = data[:4096].decode('latin-1')
    return head.startswith('GET ') and 'user-agent: docker/' in head.lower() and any('/v2/%s/' % r in head for r in repos)


def close(*socks):
    for s in socks:
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


# the client's requests on to the registry, a download asked for while held marked for the answer
def asks(c, u, conn):
    try:
        while True:
            data = c.recv(65536)
            if not data or os.path.exists(down):
                break
            if held(data):
                conn['hold'] = True
            u.sendall(data)
    except OSError:
        pass
    close(c, u)


# the registry's answers back, the body of a marked one only once nothing is held
def answers(u, c, conn):
    try:
        while True:
            data = u.recv(65536)
            if not data:
                break
            if conn.get('hold'):
                end = data.find(b'\r\n\r\n')
                if end >= 0:
                    c.sendall(data[:end + 4])
                    data = data[end + 4:]
                    conn['hold'] = False
                    while os.path.exists(hold):
                        time.sleep(0.2)
            c.sendall(data)
    except OSError:
        pass
    close(c, u)


srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', port))
srv.listen(64)
while True:
    c, _ = srv.accept()
    try:
        if os.path.exists(down):
            raise OSError
        u = socket.create_connection(('127.0.0.1', upstream))
    except OSError:
        c.close()
        continue
    conn = {}
    threading.Thread(target=asks, args=(c, u, conn), daemon=True).start()
    threading.Thread(target=answers, args=(u, c, conn), daemon=True).start()
