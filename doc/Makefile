prefix = /usr
datadir = $(prefix)/share
mandir = $(datadir)/man

txttargets = $(shell echo *.txt)
htmltargets = $(patsubst %.txt, %.html, $(txttargets))

all: docs

dist: docs

man: adhocr.8

docs: adhocr.8 $(htmltargets)

install: adhocr.8
	install -Dp -m0644 adhocr.8 $(DESTDIR)$(mandir)/man8/adhocr.8

clean:
	rm -f unconv.8 *.html *.xml

%.8.html: %.8.txt
	asciidoc -d manpage $<

%.8: %.8.xml
	@(which xmlto > /dev/null 2>&1) || \
	 (echo "*** You need to install xmlto ***"; \
	  exit 1)
	xmlto  man $<

%.html: %.txt
	@(which asciidoc > /dev/null 2>&1) || \
	 (echo "*** You need to install asciidoc ***"; \
	 exit 1)
	asciidoc $<

%.8.xml: %.8.txt
	asciidoc -b docbook -d manpage $<
