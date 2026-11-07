PREFIX = /usr/local
BINDIR = $(PREFIX)/bin
PKG_CONFIG = pkg-config

CC = cc
CFLAGS = -O2 -std=c99 -Wall -Wextra
CFLAGS += `$(PKG_CONFIG) --cflags swc wayland-client`
LDLIBS += `$(PKG_CONFIG) --libs swc wayland-client`

SRC = blitz.c

all: blitz

config.h: config.def.h
	cp config.def.h config.h

blitz: $(SRC) config.h
	$(CC) $(CFLAGS) -o blitz $(SRC) $(LDLIBS)

clean:
	rm -f blitz *.o config.h

install: blitz
	install -D -m 755 blitz $(DESTDIR)$(BINDIR)/blitz

.PHONY: all clean install
