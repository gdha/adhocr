%define rpmrelease %{nil}
%define companyname "IT3 Consultants"
%define sudogroup "wheel"

Summary: A tool to run commands on multiple systems simultaneously using expect
Name: adhocr
Version: 1.4
Release: 1%{?rpmrelease}%{?dist}
License: GPLv3
Group: Applications/File
URL: https://github.com/gdha/adhocr

Source: https://github.com/gdha/adhocr/downloads/adhocr-%{version}.tar.gz
BuildRoot: %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)

#BuildArchitectures: i386 x86_64

### Dependencies on all distributions
Requires: expect
Requires: sudo
Requires: ksh

%description
Adhoc Copy and Run (adhocr in short) is a tool to run commands on 
multiple systems at a given time. It uses expect and sudo (if required).
Run commands in batch on remote Unix systems as a plain user with a central
point of logging and output (password could be required depending on
secure key authorization setup)
We can also run commands as root with the help of sudo, but only
allow members of the 'system engineers' group to use sudo.
It is also possible to copy files to/from remote systems with logging.

%prep
%setup -q

%build

%install
%{__rm} -rf %{buildroot}
# create directories
mkdir -vp \
        %{buildroot}%{_mandir}/man8 \
        %{buildroot}%{_bindir}

# copy adhocr components into directories
cp -av doc/adhocr.8 %{buildroot}%{_mandir}/man8
cp -av adhocr %{buildroot}%{_bindir}

%post
# check for /usr/bin/ksh on Linux (probably only /bin/ksh)
if [ ! -f /usr/bin/ksh ] && [ -f /bin/ksh ]; then
	ln -s /bin/ksh /usr/bin/ksh
fi


%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root, 0755)
%doc %{_mandir}/man8/adhocr.8*
%{_bindir}/adhocr

%changelog
* Thu Jun 28 2012 Gratien D'haese ( gratien.dhaese at gmail.com ) - 1.4-1
- Initial package.
