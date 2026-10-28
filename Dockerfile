# MowBite Updater (updater.sh): the docker cli with compose, a tiny http server for its page, the mqtt client that asks
# the mower whether it's idle in its dock

# busybox's httpd and mosquitto_sub, unpacked for the target arch without running anything of it, so the image builds
# for the mower anywhere
FROM --platform=$BUILDPLATFORM alpine:3.24 AS tools
ARG TARGETARCH
RUN arch=$([ "$TARGETARCH" = arm64 ] && echo aarch64 || echo x86_64) && \
    apk add -q --root /x --arch "$arch" --initdb --no-scripts --no-cache \
      --keys-dir "/usr/share/apk/keys/$arch" --repositories-file /etc/apk/repositories busybox-extras mosquitto-clients && \
    mkdir /libs && for l in libmosquitto libcjson libssl libcrypto libcares; do cp -a /x/usr/lib/$l.so* /libs/ 2>/dev/null || true; done
# its page: what it loads named with the version of all of it (__V__ in index.html), so a browser takes the new files
# after an update and not the ones it kept. the page itself out of /www: cgi-bin/index.cgi hands it out, with
# cache-control. the type of its font: busybox's httpd knows .woff2 only from its config
COPY www /www
RUN v=$(cd /www && find . -type f -exec md5sum {} + | sort -k2 | md5sum | cut -c1-8) && \
    sed "s/__V__/$v/g" /www/index.html > /page.html && rm /www/index.html && \
    printf '.woff2:font/woff2\n' > /httpd.conf

FROM docker:29.9.2-cli
# (a busybox runs the applet its name says)
COPY --from=tools /x/bin/busybox-extras /usr/sbin/httpd
COPY --from=tools /x/usr/bin/mosquitto_sub /usr/bin/mosquitto_sub
COPY --from=tools /libs/ /usr/lib/
COPY --from=tools /httpd.conf /etc/httpd.conf
COPY lib.sh /lib.sh
COPY --chmod=755 updater.sh /updater.sh
COPY --chmod=755 self.sh /self.sh
COPY --from=tools /www /www
COPY --from=tools /page.html /page.html
ENTRYPOINT ["/updater.sh"]
