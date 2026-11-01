# a made-up github for the test (test/run.sh): the files of a folder (a query left off, as git's info/refs?service=...
# and the feeds), and <repo>/releases/latest sending where its file says: tag/v1.2.0 to that release, empty to the list
# of releases (there's none without a dash). without that file an error, as github without an answer. while the file
# "slow" is in the folder each answer takes 5 s (a look of the updater that lasts)
# python3 github.py <folder> <port>
import http.server
import os
import sys
import time

folder, port = sys.argv[1], int(sys.argv[2])


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=folder, **kwargs)

    def log_message(self, *args):
        pass

    def latest(self):
        path = self.path.split('?', 1)[0]
        if not path.endswith('/releases/latest'):
            return False
        try:
            with open(os.path.join(folder, path.lstrip('/'))) as f:
                to = f.read().strip()
        except OSError:
            self.send_error(500)
            return True
        self.send_response(302)
        self.send_header('Location', 'http://%s%s%s' % (self.headers.get('Host'), path[:-len('/latest')], '/' + to if to else ''))
        self.send_header('Content-Length', '0')
        self.end_headers()
        return True

    def slow(self):
        if os.path.exists(os.path.join(folder, 'slow')):
            time.sleep(5)

    def do_GET(self):
        self.slow()
        if not self.latest():
            super().do_GET()

    def do_HEAD(self):
        self.slow()
        if not self.latest():
            super().do_HEAD()


http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
