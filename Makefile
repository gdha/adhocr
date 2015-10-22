# Makefile for adhocr

adhocr_source = adhocr.sh
name = adhocr
specfile = spec/$(name).spec
shc_bin = /usr/local/bin/shc

##version := $(shell awk 'BEGIN { FS=":" } /Revision:/ { print $$2}' $(adhocr_source) | sed -e 's/ //g' -e 's/\$$//')
# Get the Version out of the spec file (instead of adhocr itself)
version := $(shell awk 'BEGIN { FS=":" } /^Version:/ { print $$2}' $(specfile) | sed -e 's/ //g' -e 's/\$$//')
companyname := $(shell grep '%define companyname' $(specfile) | cut -c 21- )
sudogroup := $(shell grep '%define sudogroup' $(specfile) | awk '{ print $$3 }' )

prefix = /usr
sysconfdir = /etc
bindir = $(prefix)/bin
sbindir = $(prefix)/sbin
datadir = $(prefix)/share
mandir = $(datadir)/man
localstatedir = /var


distversion = $(version)
rpmrelease =

.PHONY: doc

all:
	@echo "Nothing to build. Use \`make help' for more information."

help:
	@echo -e "adhocr make targets:\n\
\n\
  install         - Install adhocr to DESTDIR (may replace files)\n\
  dist            - Create tar file\n\
  rpm             - Create RPM package\n\
\n\
"

clean:
	@echo -e "\033[1m== Cleanup temporary files ==\033[0;0m"
	-rm -f adhocr.sh.x adhocr.sh.x.c adhocr adhocr.sh.orig

man:
	@echo -e "\033[1m== Prepare manual ==\033[0;0m"
	make -C doc man

doc:
	@echo -e "\033[1m== Prepare documentation ==\033[0;0m"
	make -C doc docs

install-bin: adhocr
	@echo -e "\033[1m== Installing binary ==\033[0;0m"
	install -Dp -m0755 $(name) $(DESTDIR)$(bindir)/$(name)

install-doc:
	@echo -e "\033[1m== Installing documentation ==\033[0;0m"
	make -C doc install

install: man install-bin install-doc

dist: clean man rewrite $(name)-$(distversion).tar.gz 

adhocr: adhocr.sh.x
	-cp -f adhocr.sh.x adhocr
	-chmod 711 adhocr

adhocr.sh.x: $(adhocr_source) rewrite shc
	/usr/local/bin/shc -r -T -f $(adhocr_source)

rewrite:
	@echo -e "\033[1m== Rewriting $(adhocr_source) ==\033[0;0m"
	sed -i.orig \
		-e 's#^Version=.*#Version=$(version)#' \
		-e 's#^CompanyName=.*#CompanyName=$(companyname)#' \
		-e 's#^SudoGroup=.*#SudoGroup=$(sudogroup)#' \
		$(adhocr_source)

shc:
	@echo -e "\033[1m== Shell Compiling $(adhocr_source) ==\033[0;0m"
	if test ! -x $(shc_bin) ; then \
		echo "Error: we need shc (http://www.datsi.fi.upm.es/~frosal/)" ; \
		exit 1 ; \
	fi

$(name)-$(distversion).tar.gz: adhocr spec/$(name).spec adhocr.sh
	@echo -e "\033[1m== Building archive $(name)-$(distversion) ==\033[0;0m"
	tar -czf $(name)-$(distversion).tar.gz --transform='s,^,$(name)-$(version)/,S' $(name) $(adhocr_source) \
		 $(specfile) Makefile doc

rpm: dist spec/$(name).spec
	@echo -e "\033[1m== Building RPM package $(name)-$(distversion)==\033[0;0m"
	rpmbuild -ta --clean \
		--define "_rpmfilename %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm" \
		--define "debug_package %{nil}" \
		--define "_rpmdir %(pwd)" $(name)-$(distversion).tar.gz


