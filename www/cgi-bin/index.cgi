#!/bin/sh
# its page (index.html, in the image as /page.html): busybox's httpd runs this for / when there's no index.html. a file
# it sends without cache-control, a browser may keep for hours and with it the files of the version before. this one
# it asks for again each time
printf 'Content-Type: text/html; charset=utf-8\r\nCache-Control: no-cache\r\n\r\n'
cat /page.html
