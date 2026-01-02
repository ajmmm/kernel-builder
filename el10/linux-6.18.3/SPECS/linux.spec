# All global changes to build and install should follow this line.

# Disable LTO in userspace packages.
%global _lto_cflags %{nil}

# The libexec directory is not used by the linker, so the shared object there
# should not be exported to RPM provides.
%global __provides_exclude_from ^%{_libexecdir}/kselftests

# Disable the find-provides.ksyms script.
%global __provided_ksyms_provides %{nil}

# All global wide changes should be above this line otherwise
# the %%install section will not see them.
%global __spec_install_pre %{___build_pre}

# Kernel has several large (hundreds of mbytes) rpms, they take ~5 mins
# to compress by single-threaded xz. Switch to threaded compression,
# and from level 2 to 3 to keep compressed sizes close to "w2" results.
#
# NB: if default compression in /usr/lib/rpm/redhat/macros ever changes,
# this one might need tweaking (e.g. if default changes to w3.xzdio,
# change below to w4T.xzdio):
%global _binary_payload w3T.xzdio

# Define the version of the Linux Kernel Archive tarball.
%global LKAver 6.18.3

# Define the buildid, if required.
#global buildid .local


# Determine the sublevel number and set pkg_version.
%define sublevel %(echo %{LKAver} | %{__awk} -F\. '{ print $3 }')
%if "%{sublevel}" == ""
%global pkg_version %{LKAver}.0
%else
%global pkg_version %{LKAver}
%endif

# Set pkg_release.
%global pkg_release 1%{?buildid}%{?dist}

### BCAT
# Further investigation is required before these features
# are enabled for the ELRepo Project kernels.
%global signkernel 0
%global signmodules 0
### BCAT

# Compress modules on all architectures that build modules.
%ifarch x86_64 || aarch64
%global zipmodules 1
%else
%global zipmodules 0
%endif

%if %{zipmodules}
%global zipsed -e 's/\.ko$/\.ko.xz/'
# For parallel xz processes. Replace with 1 to go back to single process.
%global zcpu `nproc --all`
%endif

# The following build options are enabled by default, but may become disabled
# by later architecture-specific checks. These can also be disabled by using
# --without <opt> in the rpmbuild command, or by forcing these values to 0.
#
# kernel-ml
%define with_std          %{?_without_std:          0} %{?!_without_std:          1}
#
# kernel-ml-headers
%define with_headers      %{?_without_headers:      0} %{?!_without_headers:      1}
%define with_cross_headers   %{?_without_cross_headers:   0} %{?!_without_cross_headers:   1}
#
# kernel-ml-doc
%define with_doc          %{?_without_doc:          0} %{?!_without_doc:          1}
#
# perf
%define with_perf         %{?_without_perf:         0} %{?!_without_perf:         1}
#
# tools
%define with_tools        %{?_without_tools:        0} %{?!_without_tools:        1}
#
# control whether to install the vdso directories
%define with_vdso_install %{?_without_vdso_install: 0} %{?!_without_vdso_install: 1}
#
# Additional option for toracat-friendly, one-off, kernel-ml building.
# Only build the base kernel-ml (--with baseonly):
%define with_baseonly     %{?_with_baseonly:        1} %{?!_with_baseonly:        0}

%global KVERREL %{pkg_version}-%{pkg_release}.%{_target_cpu}

# If requested, only build base kernel-ml package.
%if %{with_baseonly}
%define with_doc 0
%define with_perf 0
%define with_tools 0
%define with_vdso_install 0
%endif

%ifarch noarch
%define with_std 0
%define with_headers 0
%define with_cross_headers 0
%define with_perf 0
%define with_tools 0
%define with_vdso_install 0
%endif

%ifarch x86_64 || aarch64
%define with_doc 0
%endif

%ifarch x86_64
%define asmarch x86
%define bldarch x86_64
%define hdrarch x86_64
%define make_target bzImage
%define kernel_image arch/x86/boot/bzImage
%endif

%ifarch aarch64
%define asmarch arm64
%define bldarch arm64
%define hdrarch arm64
%define make_target Image.gz
%define kernel_image arch/arm64/boot/Image.gz
%endif

# Architectures we build tools/cpupower on
%define cpupowerarchs x86_64 aarch64

%if %{with_vdso_install}
%define use_vdso 1
%define _use_vdso 1
%else
%define _use_vdso 0
%endif

#
# Packages that need to be installed before the kernel is installed,
# as they will be used by the %%post scripts.
#
%define kernel_ml_prereq  coreutils, systemd >= 203-2, /usr/bin/kernel-install
%define initrd_prereq  dracut >= 027

Name: kernel-ml
Summary: The Linux kernel. (The core of any Linux kernel based operating system.)
License: ((GPL-2.0-only WITH Linux-syscall-note) OR BSD-2-Clause) AND ((GPL-2.0-only WITH Linux-syscall-note) OR BSD-3-Clause) AND ((GPL-2.0-only WITH Linux-syscall-note) OR CDDL-1.0) AND ((GPL-2.0-only WITH Linux-syscall-note) OR Linux-OpenIB) AND ((GPL-2.0-only WITH Linux-syscall-note) OR MIT) AND ((GPL-2.0-or-later WITH Linux-syscall-note) OR BSD-3-Clause) AND ((GPL-2.0-or-later WITH Linux-syscall-note) OR MIT) AND 0BSD AND BSD-2-Clause AND (BSD-2-Clause OR Apache-2.0) AND BSD-3-Clause AND BSD-3-Clause-Clear AND CC0-1.0 AND GFDL-1.1-no-invariants-or-later AND GPL-1.0-or-later AND (GPL-1.0-or-later OR BSD-3-Clause) AND (GPL-1.0-or-later WITH Linux-syscall-note) AND GPL-2.0-only AND (GPL-2.0-only OR Apache-2.0) AND (GPL-2.0-only OR BSD-2-Clause) AND (GPL-2.0-only OR BSD-3-Clause) AND (GPL-2.0-only OR CDDL-1.0) AND (GPL-2.0-only OR GFDL-1.1-no-invariants-or-later) AND (GPL-2.0-only OR GFDL-1.2-no-invariants-only) AND (GPL-2.0-only WITH Linux-syscall-note) AND GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause) AND (GPL-2.0-or-later OR BSD-3-Clause) AND (GPL-2.0-or-later OR CC-BY-4.0) AND (GPL-2.0-or-later WITH GCC-exception-2.0) AND (GPL-2.0-or-later WITH Linux-syscall-note) AND ISC AND LGPL-2.0-or-later AND (LGPL-2.0-or-later OR BSD-2-Clause) AND (LGPL-2.0-or-later WITH Linux-syscall-note) AND LGPL-2.1-only AND (LGPL-2.1-only OR BSD-2-Clause) AND (LGPL-2.1-only WITH Linux-syscall-note) AND LGPL-2.1-or-later AND (LGPL-2.1-or-later WITH Linux-syscall-note) AND (Linux-OpenIB OR GPL-2.0-only) AND (Linux-OpenIB OR GPL-2.0-only OR BSD-2-Clause) AND Linux-man-pages-copyleft AND MIT AND (MIT OR Apache-2.0) AND (MIT OR GPL-2.0-only) AND (MIT OR GPL-2.0-or-later) AND (MIT OR LGPL-2.1-only) AND (MPL-1.1 OR GPL-2.0-only) AND (X11 OR GPL-2.0-only) AND (X11 OR GPL-2.0-or-later) AND Zlib AND (copyleft-next-0.3.1 OR GPL-2.0-or-later)
URL: https://www.kernel.org/
Version: %{pkg_version}
Release: %{pkg_release}
ExclusiveArch: x86_64 aarch64 noarch
ExclusiveOS: Linux
Provides: kernel = %{version}-%{release}
Provides: installonlypkg(kernel)
Requires: %{name}-core-uname-r = %{KVERREL}
Requires: %{name}-modules-uname-r = %{KVERREL}

#
# List the packages required for the kernel-ml build.
#
BuildRequires: bash, bc, binutils, bison, bzip2, coreutils, diffutils, dwarves, elfutils-devel
BuildRequires: findutils, flex, gawk, gcc, gcc-c++, gcc-plugin-devel, git-core, glibc-static
BuildRequires: gzip, hmaccalc, hostname, kernel-rpm-macros >= 185-9, kmod, m4, make, net-tools
BuildRequires: patch, perl-Carp, perl-devel, perl-generators, perl-interpreter, python3-devel
BuildRequires: redhat-rpm-config, tar, which, xz

BuildRequires: openssl-devel openssl
BuildRequires: zlib-devel binutils-devel newt-devel perl(ExtUtils::Embed) bison flex xz-devel
BuildRequires: audit-libs-devel python3-setuptools
BuildRequires: java-devel
BuildRequires: libbpf-devel
BuildRequires: libbabeltrace-devel
BuildRequires: numactl-devel
BuildRequires: asciidoc, python3-sphinx, python3-sphinx_rtd_theme, xmlto
BuildRequires: gettext, libcap-devel, libcap-ng-devel, libnl3-devel
BuildRequires: ncurses-devel, pciutils-devel
BuildRequires: rsync
BuildRequires: llvm-devel
BuildRequires: clang-devel

# The following are rtla requirements
BuildRequires: python3-docutils
BuildRequires: libtraceevent-devel
BuildRequires: libtracefs-devel >= 1.6
%ifarch aarch64
BuildRequires: opencsd-devel >= 1.2.1
%endif

BuildConflicts: rhbuildsys(DiskFree) < 500Mb

###
### Sources
###
Source0: https://www.kernel.org/pub/linux/kernel/v6.x/linux-%{LKAver}.tar.xz

Source2: config-%{version}-x86_64
Source4: config-%{version}-aarch64

Source20: mod-denylist.sh
#Source21: mod-sign.sh
#Source23: x509.genkey
Source26: mod-extra.list

Source34: filter-x86_64.sh
Source37: filter-aarch64.sh
Source40: filter-modules.sh

#Source100: rheldup3.x509
#Source101: rhelkpatch1.x509

Source2002: kvm_stat.logrotate

# Do not package the source tarball.
# To build .src.rpm, run with '--with src'
%if %{?_with_src:0}%{!?_with_src:1}
NoSource: 0
%endif

%description
The %{name} meta package.

#
# This macro does requires, provides, conflicts, obsoletes for a kernel-ml package.
#	%%kernel_ml_reqprovconf <subpackage>
# It uses any kernel_ml_<subpackage>_conflicts and kernel_ml_<subpackage>_obsoletes
# macros defined above.
#
%define kernel_ml_reqprovconf \
Provides: %{name} = %{pkg_version}-%{pkg_release}\
Provides: %{name}-%{_target_cpu} = %{pkg_version}-%{pkg_release}%{?1:+%{1}}\
Provides: %{name}-drm-nouveau = 16\
Provides: %{name}-uname-r = %{KVERREL}%{?1:+%{1}}\
Requires(pre): %{kernel_ml_prereq}\
Requires(pre): %{initrd_prereq}\
Requires(pre): ((linux-firmware >= 20150904-56.git6ebf5d57) if linux-firmware)\
Recommends: linux-firmware\
Requires(preun): systemd >= 200\
Conflicts: xfsprogs < 4.3.0-1\
Conflicts: xorg-x11-drv-vmmouse < 13.0.99\
%{expand:%%{?kernel_ml%{?1:_%{1}}_conflicts:Conflicts: %%{%{name}%{?1:_%{1}}_conflicts}}}\
%{expand:%%{?kernel_ml%{?1:_%{1}}_obsoletes:Obsoletes: %%{%{name}%{?1:_%{1}}_obsoletes}}}\
%{expand:%%{?kernel_ml%{?1:_%{1}}_provides:Provides: %%{%{name}%{?1:_%{1}}_provides}}}\
# We can't let RPM do the dependencies automatically because it'll then pick up\
# a correct but undesirable perl dependency from the module headers which\
# isn't required for the kernel proper to function.\
AutoReq: no\
AutoProv: yes\
%{nil}

%package headers
Summary: Header files for the Linux kernel, used by glibc.
Obsoletes: glibc-kernheaders < 3.0-46
Provides: glibc-kernheaders = 3.0-46
%description headers
The Linux kernel headers includes the C header files that specify
the interface between the Linux kernel and userspace libraries and
programs. The header files define structures and constants that are
needed for building most standard programs and are also needed for
rebuilding the glibc package.

%package cross-headers
Summary: Header files for the Linux kernel for use by cross-glibc

%description cross-headers
Kernel-cross-headers includes the C header files that specify the interface
between the Linux kernel and userspace libraries and programs.  The
header files define structures and constants that are needed for
building most standard programs and are also needed for rebuilding the
cross-glibc package.

%package doc
Summary: Various documentation bits found in the Linux kernel source.
Group: Documentation
%description doc
This package contains documentation files from the Linux kernel
source. Various bits of information about the Linux kernel and the
device drivers shipped with it are documented in these files.

You'll want to install this package if you need a reference to the
options that can be passed to Linux kernel modules at load time.

%if %{with_perf}
%package -n perf
Summary: Performance monitoring for the Linux kernel.
Requires: bzip2
License: GPLv2
%description -n perf
This package contains the perf tool, which enables performance
monitoring of the Linux kernel.

%package -n python3-perf
Summary: Python bindings for apps which will manipulate perf events.
%description -n python3-perf
This package contains a module that permits applications written
in the Python programming language to use the interface to
manipulate perf events.

%package -n libperf
Summary: The perf library from kernel source

%description -n libperf
This package contains the kernel source perf library.


%package -n libperf-devel
Summary: Developement files for the perf library from kernel source
Requires: libperf = %{version}-%{release}

%description -n libperf-devel
This package includes libraries and header files needed for development
of applications which use perf library from kernel source.

# with_perf
%endif

%if %{with_tools}
%package -n %{name}-tools
Summary: Assortment of tools for the Linux kernel.
License: GPLv2
Obsoletes: kernel-tools < %{version}
Provides:  kernel-tools = %{version}-%{release}
Obsoletes: cpupowerutils < 1:009-0.6.p1
Provides:  cpupowerutils = 1:009-0.6.p1
Obsoletes: cpufreq-utils < 1:009-0.6.p1
Provides:  cpufreq-utils = 1:009-0.6.p1
Obsoletes: cpufrequtils < 1:009-0.6.p1
Provides:  cpufrequtils = 1:009-0.6.p1
Obsoletes: cpuspeed < 1:1.5-16
Requires: %{name}-tools-libs = %{version}-%{release}
%if "%{name}" == "kernel-ml"
Conflicts: kernel-lt-tools
%else
# it's kernel-lt
Conflicts: kernel-ml-tools
%endif
%define __requires_exclude ^%{_bindir}/python
%description -n %{name}-tools
This package contains the tools/ directory from the Linux kernel
source and the supporting documentation.

%package -n %{name}-tools-libs
Summary: Libraries for the %{name}-tools.
License: GPLv2
Obsoletes: kernel-tools-libs < %{version}
Provides:  kernel-tools-libs = %{version}-%{release}
%if "%{name}" == "kernel-ml"
Conflicts: kernel-lt-tools-libs
%else
# it's kernel-lt
Conflicts: kernel-ml-tools-libs
%endif
%description -n %{name}-tools-libs
This package contains the libraries built from the tools/ directory
of the Linux kernel source.

%package -n %{name}-tools-libs-devel
Summary: Development files for the %{name}-tools libraries.
License: GPLv2
Obsoletes: kernel-tools-libs-devel < %{version}
Provides:  kernel-tools-libs-devel = %{version}-%{release}
Obsoletes: cpupowerutils-devel < 1:009-0.6.p1
Provides:  cpupowerutils-devel = 1:009-0.6.p1
Provides: %{name}-tools-devel
Requires: %{name}-tools-libs = %{version}-%{release}
Requires: %{name}-tools = %{version}-%{release}
%if "%{name}" == "kernel-ml"
Conflicts: kernel-lt-tools-libs-devel
%else
# it's kernel-lt
Conflicts: kernel-ml-tools-libs-devel
%endif
%description -n %{name}-tools-libs-devel
This package contains the development files for the tools/ directory
of the Linux kernel source.

%package -n rtla
Summary: Real-Time Linux Analysis tools
Requires: libtraceevent
Requires: libtracefs
Requires: %{name}-tools-libs = %{version}-%{release}
%description -n rtla
The rtla meta-tool includes a set of commands that aims to analyze
the real-time properties of Linux. Instead of testing Linux as a black box,
rtla leverages kernel tracing capabilities to provide precise information
about the properties and root causes of unexpected results.

%package -n rv
Summary: RV: Runtime Verification
%description -n rv
Runtime Verification (RV) is a lightweight (yet rigorous) method that
complements classical exhaustive verification techniques (such as model
checking and theorem proving) with a more practical approach for
complex systems.
The rv tool is the interface for a collection of monitors that aim
analysing the logical and timing behavior of Linux.

# with_tools
%endif

#
# This macro creates a kernel-ml-<subpackage>-devel package.
#	%%kernel_ml_devel_package [-m] <subpackage> <pretty-name>
#
%define kernel_ml_devel_package(m) \
%package %{?1:%{1}-}devel\
Summary: Development package for building %{name} modules to match the %{?2:%{2} }%{name}.\
Provides: %{name}%{?1:-%{1}}-devel-%{_target_cpu} = %{version}-%{release}\
Provides: %{name}-devel-%{_target_cpu} = %{version}-%{release}%{?1:+%{1}}\
Provides: %{name}-devel-uname-r = %{KVERREL}%{?1:+%{1}}\
Provides: kernel%{?1:-%{1}}-devel-%{_target_cpu} = %{version}-%{release}\
Provides: kernel-devel-%{_target_cpu} = %{version}-%{release}%{?1:+%{1}}\
Provides: kernel-devel-uname-r = %{KVERREL}%{?1:+%{1}}\
Provides: kernel-devel = %{version}-%{release}%{?1:+%{1}}\
Provides: installonlypkg(kernel)\
Provides: installonlypkg(kernel-ml)\
AutoReqProv: no\
Requires(pre): findutils\
Requires: findutils\
Requires: perl-interpreter\
Requires: openssl-devel\
Requires: elfutils-libelf-devel\
Requires: bison\
Requires: flex\
Requires: make\
Requires: gcc\
%if %{-m:1}%{!-m:0}\
Requires: %{name}-devel-uname-r = %{KVERREL}\
%endif\
%description %{?1:%{1}-}devel\
This package provides %{name} headers and makefiles sufficient to build modules\
against the %{?2:%{2} }%{name} package.\
%{nil}

#
# This macro creates an empty kernel-ml-<subpackage>-devel-matched package that
# requires both the core and devel packages locked on the same version.
#	%%kernel_ml_devel_matched_package [-m] <subpackage> <pretty-name>
#
%define kernel_ml_devel_matched_package(m) \
%package %{?1:%{1}-}devel-matched\
Summary: Meta package to install matching core and devel packages for a given %{?2:%{2} }%{name}.\
Requires: %{name}%{?1:-%{1}}-devel = %{version}-%{release}\
Requires: %{name}%{?1:-%{1}}-core = %{version}-%{release}\
%description %{?1:%{1}-}devel-matched\
This meta package is used to install matching core and devel packages for a given %{?2:%{2} }%{name}.\
%{nil}

#
# This macro creates a kernel-ml-<subpackage>-modules-extra package.
#	%%kernel_ml_modules_extra_package [-m] <subpackage> <pretty-name>
#
%define kernel_ml_modules_extra_package(m) \
%package %{?1:%{1}-}modules-extra\
Summary: Extra %{name} modules to match the %{?2:%{2} }%{name}.\
Provides: %{name}%{?1:-%{1}}-modules-extra-%{_target_cpu} = %{version}-%{release}\
Provides: %{name}%{?1:-%{1}}-modules-extra-%{_target_cpu} = %{version}-%{release}%{?1:+%{1}}\
Provides: %{name}%{?1:-%{1}}-modules-extra = %{version}-%{release}%{?1:+%{1}}\
Provides: installonlypkg(kernel-module)\
Provides: installonlypkg(kernel-ml-module)\
Provides: %{name}%{?1:-%{1}}-modules-extra-uname-r = %{KVERREL}%{?1:+%{1}}\
Requires: %{name}-uname-r = %{KVERREL}%{?1:+%{1}}\
Requires: %{name}%{?1:-%{1}}-modules-uname-r = %{KVERREL}%{?1:+%{1}}\
%if %{-m:1}%{!-m:0}\
Requires: %{name}-modules-extra-uname-r = %{KVERREL}\
%endif\
AutoReq: no\
AutoProv: yes\
%description %{?1:%{1}-}modules-extra\
This package provides less commonly used %{name} modules for the %{?2:%{2} }%{name} package.\
%{nil}

#
# This macro creates a kernel-ml-<subpackage>-modules package.
#	%%kernel_ml_modules_package [-m] <subpackage> <pretty-name>
#
%define kernel_ml_modules_package(m) \
%package %{?1:%{1}-}modules\
Summary: %{name} modules to match the %{?2:%{2}-}core %{name}.\
Provides: %{name}%{?1:-%{1}}-modules-%{_target_cpu} = %{version}-%{release}\
Provides: %{name}-modules-%{_target_cpu} = %{version}-%{release}%{?1:+%{1}}\
Provides: %{name}-modules = %{version}-%{release}%{?1:+%{1}}\
Provides: installonlypkg(kernel-module)\
Provides: installonlypkg(kernel-ml-module)\
Provides: %{name}%{?1:-%{1}}-modules-uname-r = %{KVERREL}%{?1:+%{1}}\
Requires: %{name}-uname-r = %{KVERREL}%{?1:+%{1}}\
%if %{-m:1}%{!-m:0}\
Requires: %{name}-modules-uname-r = %{KVERREL}\
%endif\
AutoReq: no\
AutoProv: yes\
%description %{?1:%{1}-}modules\
This package provides commonly used %{name} modules for the %{?2:%{2}-}core %{name} package.\
%{nil}

#
# this macro creates a kernel-ml-<subpackage> meta package.
#	%%kernel_ml_meta_package <subpackage>
#
%define kernel_ml_meta_package() \
%package %{1}\
Summary: %{name} meta-package for the %{1} ${name}.\
Requires: %{name}-%{1}-core-uname-r = %{KVERREL}+%{1}\
Requires: %{name}-%{1}-modules-uname-r = %{KVERREL}+%{1}\
Provides: installonlypkg(kernel)\
Provides: installonlypkg(kernel-ml)\
%description %{1}\
The meta-package for the %{1} %{name}.\
%{nil}

#
# This macro creates a kernel-ml-<subpackage> and its -devel.
#	%%define variant_summary The Linux kernel-ml compiled for <configuration>
#	%%kernel_ml_variant_package [-n <pretty-name>] [-m] <subpackage>
#
%define kernel_ml_variant_package(n:m) \
%package %{?1:%{1}-}core\
Summary: %{variant_summary}.\
Provides: %{name}-%{?1:%{1}-}core-uname-r = %{KVERREL}%{?1:+%{1}}\
Provides: installonlypkg(kernel)\
Provides: installonlypkg(kernel-ml)\
%if %{-m:1}%{!-m:0}\
Requires: %{name}-core-uname-r = %{KVERREL}\
%endif\
%{expand:%%kernel_ml_reqprovconf}\
%if %{?1:1} %{!?1:0} \
%{expand:%%kernel_ml_meta_package %{?1:%{1}}}\
%endif\
%{expand:%%kernel_ml_devel_package %{?1:%{1}} %{!?{-n}:%{1}}%{?{-n}:%{-n*}} %{-m:%{-m}}}\
%{expand:%%kernel_ml_devel_matched_package %{?1:%{1}} %{!?{-n}:%{1}}%{?{-n}:%{-n*}} %{-m:%{-m}}}\
%{expand:%%kernel_ml_modules_package %{?1:%{1}} %{!?{-n}:%{1}}%{?{-n}:%{-n*}} %{-m:%{-m}}}\
%{expand:%%kernel_ml_modules_extra_package %{?1:%{1}} %{!?{-n}:%{1}}%{?{-n}:%{-n*}} %{-m:%{-m}}}\
%{nil}

# And, finally, the main -core package.

%define variant_summary The Linux kernel.
%kernel_ml_variant_package
%description core
The %{name} package contains the Linux kernel (vmlinuz), the core of any
Linux kernel based operating system. The %{name} package handles the basic
functions of the operating system: memory allocation, process allocation,
device input and output, etc.

# Disable the building of the debug package(s).
%global debug_package %{nil}

# Disable the creation of build_id symbolic links.
%global _build_id_links none

# Set up our "big" %%{make} macro.
%global make %{__make} -s HOSTCFLAGS="%{?build_cflags}" HOSTLDFLAGS="%{?build_ldflags}"

%prep
%ifarch x86_64 || aarch64
%if %{with_baseonly}
%if !%{with_std}
echo "Cannot build --with baseonly as the standard build is currently disabled."
exit 1
%endif
%endif
%endif

%setup -q -n %{name}-%{version} -c
mv linux-%{LKAver} linux-%{KVERREL}

pushd linux-%{KVERREL} > /dev/null

# Purge the source tree of all unrequired dot-files.
find . -name '.*' -type f -delete

# Mangle all Python shebangs to be Python 3 explicitly.
# -i specifies the interpreter for the shebang
# -n prevents creating ~backup files
# -p preserves timestamps
# This fixes errors such as
# *** ERROR: ambiguous python shebang in /usr/bin/kvm_stat: #!/usr/bin/python. Change it to python3 (or python2) explicitly.

# We patch all sources below for which we got a report/error.
## %%{log_msg "Fixing Python shebangs..."}
%py3_shebang_fix \
        tools/kvm/kvm_stat/kvm_stat \
        scripts/show_delta \
        scripts/diffconfig \
        scripts/bloat-o-meter \
        scripts/jobserver-exec \
        tools \
        Documentation \
        scripts/clang-tools 2> /dev/null


mv COPYING COPYING-%{version}-%{release}

cp -a %{SOURCE2} .
cp -a %{SOURCE4} .

# Set the EXTRAVERSION string in the top level Makefile.
sed -i "s@^EXTRAVERSION.*@EXTRAVERSION = -%{release}.%{_target_cpu}@" Makefile

%ifarch x86_64 || aarch64
cp config-%{version}-%{_target_cpu} .config
%{__make} -s ARCH=%{bldarch} listnewconfig | grep -E '^CONFIG_' > newoptions-el-%{_target_cpu}.txt || true
if [ -s newoptions-el10-%{_target_cpu}.txt ]; then
	cat newoptions-el10-%{_target_cpu}.txt
	exit 1
fi
rm -f newoptions-el10-%{_target_cpu}.txt
%endif

# Adjust the FIPS module name for RHEL9.
for i in config-%{version}-*; do
	sed -i 's@CONFIG_CRYPTO_FIPS_NAME=.*@CONFIG_CRYPTO_FIPS_NAME="Red Hat Enterprise Linux 9 - Kernel Cryptographic API"@' $i
done

%{__make} -s distclean

popd > /dev/null

%build
pushd linux-%{KVERREL} > /dev/null

%ifarch x86_64 || aarch64
cp config-%{version}-%{_target_cpu} .config

%{__make} -s ARCH=%{bldarch} oldconfig


%if %{with_std}
%{make} %{?_smp_mflags} ARCH=%{bldarch} %{make_target}

%{make} %{?_smp_mflags} ARCH=%{bldarch} modules || exit 1

%ifarch aarch64
%{make} %{?_smp_mflags} ARCH=%{bldarch} dtbs
%endif

%endif

%if %{with_perf}
%ifarch aarch64
%global perf_build_extra_opts CORESIGHT=1
%endif

%global perf_make \
	%{__make} -s EXTRA_CFLAGS="%{?build_cflags}" EXTRA_CXXFLAGS="%{?build_cxxflags}"  LDFLAGS="%{?build_ldflags} -Wl,-E" -C tools/perf V=1 NO_PERF_READ_VDSO32=1 NO_PERF_READ_VDSOX32=1 WERROR=0 NO_LIBUNWIND=1 HAVE_CPLUS_DEMANGLE=1 NO_GTK2=1 NO_STRLCPY=1 NO_BIONIC=1 LIBBPF_DYNAMIC=1 LIBTRACEEVENT_DYNAMIC=1 %{?perf_build_extra_opts} prefix=%{_prefix} PYTHON=%{__python3}

# Make sure that check-headers.sh is executable.
chmod +x tools/perf/check-headers.sh

%{perf_make} all

%global libperf_make \
	%{make} EXTRA_CFLAGS="%{?build_cflags}" LDFLAGS="%{?build_ldflags}" -C tools/lib/perf

# with_perf
%endif

%global tools_make \
  CFLAGS="${RPM_OPT_FLAGS}" LDFLAGS="%{__global_ldflags}" EXTRA_CFLAGS="${RPM_OPT_FLAGS}" %{make} %{?make_opts}

# link against in-tree libcpupower for idle state support
%global rtla_make %{tools_make} LDFLAGS="%{__global_ldflags} -L../../power/cpupower" INCLUDES="-I../../power/cpupower/lib"

%if %{with_tools}
# Make sure that version-gen.sh is executable.
chmod +x tools/power/cpupower/utils/version-gen.sh
%{tools_make} %{?_smp_mflags} -C tools/power/cpupower CPUFREQ_BENCH=false DEBUG=false

%ifarch x86_64
   pushd tools/power/cpupower/debug/x86_64
   %{tools_make} centrino-decode powernow-k8-decode
   popd
   pushd tools/power/x86/x86_energy_perf_policy/
   %{tools_make}
   popd
   pushd tools/power/x86/turbostat
   %{tools_make}
   popd
   pushd tools/power/x86/intel-speed-select
   %{tools_make}
   popd
   pushd tools/arch/x86/intel_sdsi
   %{tools_make} CFLAGS="${RPM_OPT_FLAGS}"
   popd
%endif

pushd tools/thermal/tmon/
%{tools_make}
popd
pushd tools/bootconfig/
%{tools_make}
popd
pushd tools/iio/
%{tools_make}
popd
pushd tools/gpio/
%{tools_make}
popd

# build VM tools
pushd tools/mm/
%{tools_make} slabinfo page_owner_sort
popd
pushd tools/verification/rv/
%{tools_make}
popd
pushd tools/tracing/rtla
%{rtla_make}
popd

%endif

%endif

popd > /dev/null

%install
%define __modsign_install_post \
if [ "%{zipmodules}" -eq "1" ]; then \
	find %{buildroot}/lib/modules/ -name '*.ko' -type f | xargs --no-run-if-empty -P%{zcpu} xz \
fi \
%{nil}

#
# Ensure modules are signed *after* all invocations of
# strip have occured, which are in __os_install_post.
#
%define __spec_install_post \
	%{__arch_install_post}\
	%{__os_install_post}\
	%{__modsign_install_post}

pushd linux-%{KVERREL} > /dev/null

rm -fr %{buildroot}

%ifarch x86_64 || aarch64
mkdir -p %{buildroot}

%if %{with_std}
mkdir -p %{buildroot}/boot
mkdir -p %{buildroot}%{_libexecdir}
mkdir -p %{buildroot}/lib/modules/%{KVERREL}
mkdir -p %{buildroot}/lib/modules/%{KVERREL}/systemtap

%ifarch aarch64
%{make} ARCH=%{bldarch} dtbs_install INSTALL_DTBS_PATH=%{buildroot}/boot/dtb-%{KVERREL}
cp -r %{buildroot}/boot/dtb-%{KVERREL} %{buildroot}/lib/modules/%{KVERREL}/dtb
find arch/%{bldarch}/boot/dts -name '*.dtb' -type f -delete
%endif

# Install the results within the RPM_BUILD_ROOT directory.
%{__install} -m 644 .config %{buildroot}/boot/config-%{KVERREL}
%{__install} -m 644 .config %{buildroot}/lib/modules/%{KVERREL}/config
%{__install} -m 644 System.map %{buildroot}/boot/System.map-%{KVERREL}
%{__install} -m 644 System.map %{buildroot}/lib/modules/%{KVERREL}/System.map

# We estimate the size of the initramfs because rpm needs to take this size
# into consideration when performing disk space calculations. (See bz #530778)
dd if=/dev/zero of=%{buildroot}/boot/initramfs-%{KVERREL}.img bs=1M count=20


cp %{kernel_image} %{buildroot}/boot/vmlinuz-%{KVERREL}
chmod 755 %{buildroot}/boot/vmlinuz-%{KVERREL}
cp %{buildroot}/boot/vmlinuz-%{KVERREL} %{buildroot}/lib/modules/%{KVERREL}/vmlinuz

sha512hmac %{buildroot}/boot/vmlinuz-%{KVERREL} | sed -e "s,%{buildroot},," > %{buildroot}/boot/.vmlinuz-%{KVERREL}.hmac
cp %{buildroot}/boot/.vmlinuz-%{KVERREL}.hmac %{buildroot}/lib/modules/%{KVERREL}/.vmlinuz.hmac

# Override mod-fw because we don't want it to install any firmware.
# We'll get it from the linux-firmware package and we don't want conflicts.
%{make} %{?_smp_mflags} ARCH=%{bldarch} INSTALL_MOD_PATH=%{buildroot} modules_install KERNELRELEASE=%{KVERREL} mod-fw=
    
# Add a noop %%defattr statement because rpm doesn't like empty file list files.
echo '%%defattr(-,-,-)' > ../%{name}-ldsoconf.list

%if %{with_vdso_install}
%{make} %{?_smp_mflags} ARCH=%{bldarch} INSTALL_MOD_PATH=%{buildroot} vdso_install KERNELRELEASE=%{KVERREL}

if [ -s ldconfig-%{name}.conf ]; then
	install -D -m 444 ldconfig-%{name}.conf %{buildroot}/etc/ld.so.conf.d/%{name}-%{KVERREL}.conf
	echo /etc/ld.so.conf.d/%{name}-%{KVERREL}.conf >> ../%{name}-ldsoconf.list
fi
%endif

#
# This looks scary but the end result is supposed to be:
#
# - all arch relevant include/ files.
# - all Makefile and Kconfig files.
# - all script/ files.
#
rm -f %{buildroot}/lib/modules/%{KVERREL}/build
rm -f %{buildroot}/lib/modules/%{KVERREL}/source
mkdir -p %{buildroot}/lib/modules/%{KVERREL}/build

pushd %{buildroot}/lib/modules/%{KVERREL} > /dev/null
ln -s build source
popd > /dev/null

mkdir -p %{buildroot}/lib/modules/%{KVERREL}/updates
mkdir -p %{buildroot}/lib/modules/%{KVERREL}/weak-updates

# CONFIG_KERNEL_HEADER_TEST generates some extra files during testing so just delete them.
find . -name *.h.s -delete

# First copy everything . . .
cp --parents `find  -type f -name "Makefile*" -o -name "Kconfig*"` %{buildroot}/lib/modules/%{KVERREL}/build

if [ ! -e Module.symvers ]; then
	touch Module.symvers
fi

cp Module.symvers %{buildroot}/lib/modules/%{KVERREL}/build
cp System.map %{buildroot}/lib/modules/%{KVERREL}/build

if [ -s Module.markers ]; then
	cp Module.markers %{buildroot}/lib/modules/%{KVERREL}/build
fi

gzip -c9 < Module.symvers > %{buildroot}/boot/symvers-%{KVERREL}.gz
cp %{buildroot}/boot/symvers-%{KVERREL}.gz %{buildroot}/lib/modules/%{KVERREL}/symvers.gz

# . . . then drop all but the needed Makefiles and Kconfig files.
rm -fr %{buildroot}/lib/modules/%{KVERREL}/build/scripts
rm -fr %{buildroot}/lib/modules/%{KVERREL}/build/include
cp .config %{buildroot}/lib/modules/%{KVERREL}/build
cp -a scripts %{buildroot}/lib/modules/%{KVERREL}/build
rm -fr %{buildroot}/lib/modules/%{KVERREL}/build/scripts/tracing
rm -f %{buildroot}/lib/modules/%{KVERREL}/build/scripts/spdxcheck.py

# Files for 'make scripts' to succeed with kernel-ml-devel.
mkdir -p %{buildroot}/lib/modules/%{KVERREL}/build/security/selinux/include
cp -a --parents security/selinux/include/classmap.h %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents security/selinux/include/initial_sid_to_string.h %{buildroot}/lib/modules/%{KVERREL}/build
mkdir -p %{buildroot}/lib/modules/%{KVERREL}/build/tools/include/tools
cp -a --parents tools/include/tools/be_byteshift.h %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/tools/le_byteshift.h %{buildroot}/lib/modules/%{KVERREL}/build

# Files for 'make prepare' to succeed with kernel-ml-devel.
cp -a --parents tools/include/linux/compiler* %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/linux/types.h %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/build/Build.include %{buildroot}/lib/modules/%{KVERREL}/build
# cp --parents tools/build/Build %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/build/fixdep.c %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/objtool/sync-check.sh %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/bpf/resolve_btfids %{buildroot}/lib/modules/%{KVERREL}/build

cp --parents security/selinux/include/policycap_names.h %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents security/selinux/include/policycap.h %{buildroot}/lib/modules/%{KVERREL}/build

cp -a --parents tools/include/asm-generic %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/linux %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/uapi/asm %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/uapi/asm-generic %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/uapi/linux %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/include/vdso %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/scripts/utilities.mak %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/lib/subcmd %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/lib/*.c %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/objtool/*.[ch] %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/objtool/Build %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/objtool/include/objtool/*.h %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/lib/bpf %{buildroot}/lib/modules/%{KVERREL}/build
cp --parents tools/lib/bpf/Build %{buildroot}/lib/modules/%{KVERREL}/build

if [ -f tools/objtool/objtool ]; then
	cp -a tools/objtool/objtool %{buildroot}/lib/modules/%{KVERREL}/build/tools/objtool/ || :
fi
if [ -f tools/objtool/fixdep ]; then
	cp -a tools/objtool/fixdep %{buildroot}/lib/modules/%{KVERREL}/build/tools/objtool/ || :
fi
if [ -d arch/%{bldarch}/scripts ]; then
	cp -a arch/%{bldarch}/scripts %{buildroot}/lib/modules/%{KVERREL}/build/arch/%{_arch} || :
fi
if [ -f arch/%{bldarch}/*lds ]; then
	cp -a arch/%{bldarch}/*lds %{buildroot}/lib/modules/%{KVERREL}/build/arch/%{_arch}/ || :
fi
if [ -f arch/%{asmarch}/kernel/module.lds ]; then
	cp -a --parents arch/%{asmarch}/kernel/module.lds %{buildroot}/lib/modules/%{KVERREL}/build/
fi

find %{buildroot}/lib/modules/%{KVERREL}/build/scripts \( -iname "*.o" -o -iname "*.cmd" \) -exec rm -f {} +

if [ -d arch/%{asmarch}/include ]; then
	cp -a --parents arch/%{asmarch}/include %{buildroot}/lib/modules/%{KVERREL}/build/
fi

%ifarch aarch64
# arch/arm64/include/asm/xen references arch/arm
cp -a --parents arch/arm/include/asm/xen %{buildroot}/lib/modules/%{KVERREL}/build/
# arch/arm64/include/asm/opcodes.h references arch/arm
cp -a --parents arch/arm/include/asm/opcodes.h %{buildroot}/lib/modules/%{KVERREL}/build/
%endif

cp -a include %{buildroot}/lib/modules/%{KVERREL}/build/include

%ifarch x86_64
# Files required for 'make prepare' to succeed with kernel-ml-devel.
cp -a --parents arch/x86/entry/syscalls/syscall_32.tbl %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/entry/syscalls/syscall_64.tbl %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/tools/relocs_32.c %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/tools/relocs_64.c %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/tools/relocs.c %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/tools/relocs_common.c %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/tools/relocs.h %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/purgatory/purgatory.c %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/purgatory/stack.S %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/purgatory/setup-x86_64.S %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/purgatory/entry64.S %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/boot/string.h %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/boot/string.c %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents arch/x86/boot/ctype.h %{buildroot}/lib/modules/%{KVERREL}/build/

cp -a --parents scripts/syscalltbl.sh %{buildroot}/lib/modules/%{KVERREL}/build/
cp -a --parents scripts/syscallhdr.sh %{buildroot}/lib/modules/%{KVERREL}/build/

cp -a --parents tools/arch/x86/include/asm %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/arch/x86/include/uapi/asm %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/objtool/arch/x86/lib %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/arch/x86/lib/ %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/arch/x86/tools/gen-insn-attr-x86.awk %{buildroot}/lib/modules/%{KVERREL}/build
cp -a --parents tools/objtool/arch/x86/ %{buildroot}/lib/modules/%{KVERREL}/build
%endif

# Clean up the intermediate tools files.
find %{buildroot}/lib/modules/%{KVERREL}/build/tools \( -iname "*.o" -o -iname "*.cmd" \) -exec rm -f {} +

# Make sure that the Makefile and the version.h file have a matching timestamp
# so that external modules can be built.
touch -r %{buildroot}/lib/modules/%{KVERREL}/build/Makefile \
	%{buildroot}/lib/modules/%{KVERREL}/build/include/generated/uapi/linux/version.h

find %{buildroot}/lib/modules/%{KVERREL} -name "*.ko" -type f > modnames

# Mark the modules executable, so that strip-to-file can strip them.
xargs --no-run-if-empty chmod u+x < modnames

# Generate a list of modules for block and networking.
grep -F /drivers/ modnames | xargs --no-run-if-empty nm -upA | \
	sed -n 's,^.*/\([^/]*\.ko\):  *U \(.*\)$,\1 \2,p' > drivers.undef

collect_modules_list()
{
	sed -r -n -e "s/^([^ ]+) \\.?($2)\$/\\1/p" drivers.undef | \
		LC_ALL=C sort -u > %{buildroot}/lib/modules/%{KVERREL}/modules.$1

	if [ ! -z "$3" ]; then
		sed -r -e "/^($3)\$/d" -i %{buildroot}/lib/modules/%{KVERREL}/modules.$1
	fi
}

collect_modules_list networking \
    'register_netdev|ieee80211_register_hw|usbnet_probe|phy_driver_register|rt(l_|2x00)(pci|usb)_probe|register_netdevice'

collect_modules_list block \
    'ata_scsi_ioctl|scsi_add_host|scsi_add_host_with_dma|blk_alloc_queue|blk_init_queue|register_mtd_blktrans|scsi_esp_register|scsi_register_device_handler|blk_queue_physical_block_size' 'pktcdvd.ko|dm-mod.ko'

collect_modules_list drm \
    'drm_open|drm_init'

collect_modules_list modesetting \
    'drm_crtc_init'

# Detect any missing or incorrect license tags.
( find %{buildroot}/lib/modules/%{KVERREL} -name '*.ko' -type f | xargs --no-run-if-empty /sbin/modinfo -l | \
	grep -E -v 'GPL( v2)?$|Dual BSD/GPL$|Dual MPL/GPL$|GPL and additional rights$' ) && exit 1

remove_depmod_files()
{
	# Remove all the files that will be auto generated by depmod at the kernel install time.
	pushd %{buildroot}/lib/modules/%{KVERREL} > /dev/null
	rm -f modules.{alias,alias.bin,builtin.alias.bin,builtin.bin} \
		modules.{dep,dep.bin,devname,softdep,symbols,symbols.bin}
	popd > /dev/null
}

remove_depmod_files

# Identify modules in the kernel-ml-modules-extras package
%{SOURCE20} %{buildroot} lib/modules/%{KVERREL} %{SOURCE26}

#
# Generate the kernel-ml-core and kernel-ml-modules file lists.
#

# Make a copy of the System.map file for depmod to use.
cp System.map %{buildroot}/

pushd %{buildroot} > /dev/null

# Create a backup of the full module tree so it can be
# restored after the filtering has been completed.
mkdir restore
cp -r lib/modules/%{KVERREL}/* restore/

# Don't include anything going into kernel-ml-modules-extra in the file lists.
xargs rm -fr < mod-extra.list

# Find all the module files and filter them out into the core and modules lists.
# This actually removes anything going into kernel-ml-modules from the directory.
find lib/modules/%{KVERREL}/kernel -name *.ko -type f | sort -n > modules.list
cp $RPM_SOURCE_DIR/filter-*.sh .
./filter-modules.sh modules.list %{_target_cpu}
rm -f filter-*.sh

# Go back and find all of the various directories in the tree.
# We use this for the directory lists in kernel-ml-core.
find lib/modules/%{KVERREL}/kernel -mindepth 1 -type d | sort -n > module-dirs.list

# Cleanup.
rm -f System.map
cp -r restore/* lib/modules/%{KVERREL}/
rm -fr restore

popd > /dev/null

# Make sure that the files lists start with absolute paths or rpmbuild fails.
# Also add in the directory entries.
sed -e 's/^lib*/\/lib/' %{?zipsed} %{buildroot}/k-d.list > ../%{name}-modules.list
sed -e 's/^lib*/%dir \/lib/' %{?zipsed} %{buildroot}/module-dirs.list > ../%{name}-core.list
sed -e 's/^lib*/\/lib/' %{?zipsed} %{buildroot}/modules.list >> ../%{name}-core.list
sed -e 's/^lib*/\/lib/' %{?zipsed} %{buildroot}/mod-extra.list >> ../%{name}-modules-extra.list

# Cleanup.
rm -f %{buildroot}/k-d.list
rm -f %{buildroot}/module-dirs.list
rm -f %{buildroot}/modules.list
rm -f %{buildroot}/mod-extra.list

# Move the development files out of the /lib/modules/ file system.
mkdir -p %{buildroot}/usr/src/kernels
mv %{buildroot}/lib/modules/%{KVERREL}/build %{buildroot}/usr/src/kernels/%{KVERREL}

# This is going to create a broken link during the build but we don't use
# it after this point. We need the link to actually point to something
# for when the kernel-ml-devel package is installed.
ln -sf /usr/src/kernels/%{KVERREL} %{buildroot}/lib/modules/%{KVERREL}/build

# Move the generated vmlinux.h file into the kernel-ml-devel directory structure.
### if [ -f tools/bpf/bpftool/vmlinux.h ]; then
###	mv tools/bpf/bpftool/vmlinux.h %{buildroot}/usr/src/kernels/%{KVERREL}/
### fi

# Purge the kernel-ml-devel tree of leftover junk.
find %{buildroot}/usr/src/kernels -name ".*.cmd" -type f -delete

%endif

# We have to do the headers install before the tools install because the
# kernel-ml headers_install will remove any header files in /usr/include that
# it doesn't install itself.

%if %{with_headers}
# Install kernel-ml headers
%{__make} -s ARCH=%{hdrarch} INSTALL_HDR_PATH=%{buildroot}/usr headers_install

find %{buildroot}/usr/include \
  \( -name .install -o -name .check -o \
     -name ..install.cmd -o -name ..check.cmd \) -delete
%endif

%if %{with_cross_headers}
HDR_ARCH_LIST='arm64 powerpc s390 x86 riscv'
mkdir -p %{buildroot}/usr/tmp-headers

for arch in $HDR_ARCH_LIST; do
	mkdir %{buildroot}/usr/tmp-headers/arch-${arch}
	%{__make} ARCH=${arch} INSTALL_HDR_PATH=%{buildroot}/usr/tmp-headers/arch-${arch} headers_install
done

find %{buildroot}/usr/tmp-headers \
     \( -name .install -o -name .check -o \
        -name ..install.cmd -o -name ..check.cmd \) -delete

# Copy all the architectures we care about to their respective asm directories
for arch in $HDR_ARCH_LIST ; do
	mkdir -p %{buildroot}/usr/${arch}-linux-gnu/include
	mv %{buildroot}/usr/tmp-headers/arch-${arch}/include/* %{buildroot}/usr/${arch}-linux-gnu/include/
done

rm -rf %{buildroot}/usr/tmp-headers
%endif

%if %{with_perf}
# perf tool binary and supporting scripts/binaries
%{perf_make} DESTDIR=%{buildroot} lib=%{_lib} install-bin
%{__install} -m 644 -D -t %{buildroot}/%{_docdir}/perf tools/perf/Documentation/examples.txt
# Remove the 'trace' symlink.
rm -f %{buildroot}%{_bindir}/trace

# For both of the below, yes, this should be using a macro but right now
# it's hard coded and we don't actually want it anyway.
# Remove examples.
rm -fr %{buildroot}/usr/lib/perf/examples
rm -fr %{buildroot}/usr/lib/perf/include

# python-perf extension
%{perf_make} DESTDIR=%{buildroot} install-python_ext

# perf man pages (note: implicit rpm magic compresses them later)
mkdir -p %{buildroot}%{_mandir}/man1
%{perf_make} DESTDIR=%{buildroot} install-man

# Remove any tracevent files, eg. its plugins still gets built and installed,
# even if we build against system's libtracevent during perf build (by setting
# LIBTRACEEVENT_DYNAMIC=1 above in perf_make macro). Those files should already
# ship with libtraceevent package.
rm -fr %{buildroot}%{_libdir}/traceevent

# libperf
%{libperf_make} -j 1 DESTDIR=%{buildroot} prefix=%{_prefix} libdir=%{_libdir} install install_headers

%endif

%if %{with_tools}
%{__make} -s -C tools/power/cpupower DESTDIR=%{buildroot} libdir=%{_libdir} mandir=%{_mandir} CPUFREQ_BENCH=false install

%{__rm} -f $RPM_BUILD_ROOT%{_libdir}/*.{a,la}
%{__rm} -f $RPM_BUILD_ROOT%{_sysconfdir}/cpupower-service.conf
%{__rm} -f $RPM_BUILD_ROOT%{_libexecdir}/cpupower
%{__rm} -f $RPM_BUILD_ROOT%{_unitdir}/cpupower.service

%find_lang cpupower
mv cpupower.lang ../

%ifarch x86_64
pushd tools/power/cpupower/debug/x86_64 > /dev/null
%{__install} -m755 centrino-decode %{buildroot}%{_bindir}/centrino-decode
%{__install} -m755 powernow-k8-decode %{buildroot}%{_bindir}/powernow-k8-decode
popd > /dev/null
%endif

chmod 0755 %{buildroot}%{_libdir}/libcpupower.so*
mkdir -p %{buildroot}%{_unitdir} %{buildroot}%{_sysconfdir}/sysconfig

%ifarch x86_64
mkdir -p %{buildroot}%{_mandir}/man8
pushd tools/power/x86/x86_energy_perf_policy > /dev/null
%{__make} -s %{?_smp_mflags} DESTDIR=%{buildroot} install
popd > /dev/null

pushd tools/power/x86/turbostat > /dev/null
%{__make} -s %{?_smp_mflags} DESTDIR=%{buildroot} install
popd > /dev/null

pushd tools/power/x86/intel-speed-select > /dev/null
%{__make} -s %{?_smp_mflags} DESTDIR=%{buildroot} install
popd > /dev/null
%endif

pushd tools/thermal/tmon > /dev/null
%{__make} -s %{?_smp_mflags} INSTALL_ROOT=%{buildroot} install
popd > /dev/null

pushd tools/iio > /dev/null
%{__make} -s %{?_smp_mflags} DESTDIR=%{buildroot} install
popd > /dev/null

pushd tools/gpio > /dev/null
%{__make} -s %{?_smp_mflags} DESTDIR=%{buildroot} install
popd > /dev/null

%{__install} -m644 -D %{SOURCE2002} %{buildroot}%{_sysconfdir}/logrotate.d/kvm_stat

pushd tools/kvm/kvm_stat > /dev/null
%{__make} -s INSTALL_ROOT=%{buildroot} install-tools
%{__make} -s INSTALL_ROOT=%{buildroot} install-man
%{__install} -m644 -D kvm_stat.service %{buildroot}%{_unitdir}/kvm_stat.service
popd > /dev/null

# install VM tools
pushd tools/mm/
%{__install} -m755 slabinfo %{buildroot}%{_bindir}/slabinfo
%{__install} -m755 page_owner_sort %{buildroot}%{_bindir}/page_owner_sort
popd
pushd tools/verification/rv/
%{tools_make} DESTDIR=%{buildroot} install
popd
pushd tools/tracing/rtla/
%{tools_make} DESTDIR=%{buildroot} install
rm -f %{buildroot}%{_bindir}/hwnoise
rm -f %{buildroot}%{_bindir}/osnoise
rm -f %{buildroot}%{_bindir}/timerlat
(cd %{buildroot}

        ln -sf rtla ./%{_bindir}/hwnoise
        ln -sf rtla ./%{_bindir}/osnoise
        ln -sf rtla ./%{_bindir}/timerlat
)
popd

%endif

%endif

%ifarch noarch
mkdir -p %{buildroot}

%if %{with_doc}
# Sometimes non-world-readable files sneak into the kernel source tree.
chmod -R a=rX Documentation
find Documentation -type d | xargs --no-run-if-empty chmod u+w

DocDir=%{buildroot}%{_datadir}/doc/%{name}-doc-%{version}-%{release}

# Copy the source over.
mkdir -p $DocDir
tar -h -f - --exclude=man --exclude='.*' -c Documentation | tar xf - -C $DocDir
%endif
%endif

popd > /dev/null

###
### Scripts.
###
%if %{with_tools}
%post -n %{name}-tools-libs
/sbin/ldconfig

%postun -n %{name}-tools-libs
/sbin/ldconfig
%endif

#
# This macro defines a %%post script for a kernel-ml*-devel package.
#	%%kernel_ml_devel_post [<subpackage>]
# Note we don't run hardlink if ostree is in use, as ostree is
# a far more sophisticated hardlink implementation.
# https://github.com/projectatomic/rpm-ostree/commit/58a79056a889be8814aa51f507b2c7a4dccee526
#
%define kernel_ml_devel_post() \
%{expand:%%post %{?1:%{1}-}devel}\
if [ -f /etc/sysconfig/kernel ]\
then\
    . /etc/sysconfig/kernel || exit $?\
fi\
if [ "$HARDLINK" != "no" -a -x /usr/bin/hardlink -a ! -e /run/ostree-booted ] \
then\
    (cd /usr/src/kernels/%{KVERREL}%{?1:+%{1}} &&\
        /usr/bin/find . -type f | while read f; do\
          hardlink -c /usr/src/kernels/*%{?dist}.*/$f $f > /dev/null\
        done)\
fi\
%{nil}

#
# This macro defines a %%post script for a kernel-ml*-modules-extra package.
# It also defines a %%postun script that does the same thing.
#	%%kernel_ml_modules_extra_post [<subpackage>]
#
%define kernel_ml_modules_extra_post() \
%{expand:%%post %{?1:%{1}-}modules-extra}\
/sbin/depmod -a %{KVERREL}%{?1:+%{1}}\
%{nil}\
%{expand:%%postun %{?1:%{1}-}modules-extra}\
/sbin/depmod -a %{KVERREL}%{?1:+%{1}}\
%{nil}

#
# This macro defines a %%post script for a kernel-ml*-modules package.
# It also defines a %%postun script that does the same thing.
#	%%kernel_ml_modules_post [<subpackage>]
#
%define kernel_ml_modules_post() \
%{expand:%%post %{?1:%{1}-}modules}\
/sbin/depmod -a %{KVERREL}%{?1:+%{1}}\
if [ ! -f %{_localstatedir}/lib/rpm-state/%{name}/installing_core_%{KVERREL}%{?1:+%{1}} ]; then\
	mkdir -p %{_localstatedir}/lib/rpm-state/%{name}\
	touch %{_localstatedir}/lib/rpm-state/%{name}/need_to_run_dracut_%{KVERREL}%{?1:+%{1}}\
fi\
%{nil}\
%{expand:%%postun %{?1:%{1}-}modules}\
/sbin/depmod -a %{KVERREL}%{?1:+%{1}}\
%{nil}\
%{expand:%%posttrans %{?1:%{1}-}modules}\
if [ -f %{_localstatedir}/lib/rpm-state/%{name}/need_to_run_dracut_%{KVERREL}%{?1:+%{1}} ]; then\
	rm -f %{_localstatedir}/lib/rpm-state/%{name}/need_to_run_dracut_%{KVERREL}%{?1:+%{1}}\
	echo "Running: dracut -f --kver %{KVERREL}%{?1:+%{1}}"\
	dracut -f --kver "%{KVERREL}%{?1:+%{1}}" || exit $?\
fi\
%{nil}

# This macro defines a %%posttrans script for a kernel-ml package.
#	%%kernel_ml_variant_posttrans [<subpackage>]
# More text can follow to go at the end of this variant's %%post.
#
%define kernel_ml_variant_posttrans() \
%{expand:%%posttrans %{?1:%{1}-}core}\
if [ -x %{_sbindir}/weak-modules ]\
then\
    %{_sbindir}/weak-modules --add-kernel %{KVERREL}%{?1:+%{1}} || exit $?\
fi\
rm -f %{_localstatedir}/lib/rpm-state/%{name}/installing_core_%{KVERREL}%{?-v:+%{-v*}}\
/bin/kernel-install add %{KVERREL}%{?1:+%{1}} /lib/modules/%{KVERREL}%{?1:+%{1}}/vmlinuz || exit $?\
%{nil}

#
# This macro defines a %%post script for a kernel-ml package and its devel package.
#	%%kernel_ml_variant_post [-v <subpackage>] [-r <replace>]
# More text can follow to go at the end of this variant's %%post.
#
%define kernel_ml_variant_post(v:r:) \
%{expand:%%kernel_ml_devel_post %{?-v*}}\
%{expand:%%kernel_ml_modules_post %{?-v*}}\
%{expand:%%kernel_ml_modules_extra_post %{?-v*}}\
%{expand:%%kernel_ml_variant_posttrans %{?-v*}}\
%{expand:%%post %{?-v*:%{-v*}-}core}\
%{-r:\
if [ `uname -i` == "x86_64" ] &&\
    [ -f /etc/sysconfig/kernel ]; then\
    /bin/sed -r -i -e 's/^DEFAULTKERNEL=%{-r*}$/DEFAULTKERNEL=%{name}%{?-v:-%{-v*}}/' /etc/sysconfig/kernel || exit $?\
fi}\
mkdir -p %{_localstatedir}/lib/rpm-state/%{name}\
touch %{_localstatedir}/lib/rpm-state/%{name}/installing_core_%{KVERREL}%{?-v:+%{-v*}}\
%{nil}

#
# This macro defines a %%preun script for a kernel-ml package.
#	%%kernel_ml_variant_preun <subpackage>
#
%define kernel_ml_variant_preun() \
%{expand:%%preun %{?1:%{1}-}core}\
/bin/kernel-install remove %{KVERREL}%{?1:+%{1}} /lib/modules/%{KVERREL}%{?1:+%{1}}/vmlinuz || exit $?\
if [ -x %{_sbindir}/weak-modules ]\
then\
    %{_sbindir}/weak-modules --remove-kernel %{KVERREL}%{?1:+%{1}} || exit $?\
fi\
%{nil}

%kernel_ml_variant_preun
%kernel_ml_variant_post -r kernel-smp

if [ -x /sbin/ldconfig ]
then
    /sbin/ldconfig -X || exit $?
fi

###
### File lists.
###
%if %{with_headers}
%files headers
%{_includedir}/*
%exclude %{_includedir}/cpufreq.h
%endif

%if %{with_cross_headers}
%files cross-headers
%{_prefix}/*-linux-gnu/include/*
%endif

%if %{with_doc}
%files doc
%defattr(-,root,root)
%{_datadir}/doc/%{name}-doc-%{version}-%{release}/Documentation/*
%dir %{_datadir}/doc/%{name}-doc-%{version}-%{release}/Documentation
%dir %{_datadir}/doc/%{name}-doc-%{version}-%{release}
%endif

%if %{with_perf}
%files -n perf
%{_bindir}/perf
%{_docdir}/perf*
%{_includedir}/perf/perf_dlfilter.h
%{_libdir}/libperf-jvmti.so
%dir %{_libexecdir}/perf-core
%{_libexecdir}/perf-core/*
%{_mandir}/man[1-8]/perf*
%{_sysconfdir}/bash_completion.d/perf

%files -n python3-perf
%{python3_sitearch}/*

%files -n libperf
%{_libdir}/libperf.so.0
%{_libdir}/libperf.so.0.0.1

%files -n libperf-devel
%{_docdir}/libperf
%{_includedir}/internal/*.h
%{_includedir}/perf/bpf_perf.h
%{_includedir}/perf/core.h
%{_includedir}/perf/cpumap.h
%{_includedir}/perf/event.h
%{_includedir}/perf/evlist.h
%{_includedir}/perf/evsel.h
%{_includedir}/perf/mmap.h
%{_includedir}/perf/threadmap.h
%{_libdir}/libperf.so
%{_libdir}/pkgconfig/libperf.pc
%{_mandir}/man*/libperf*

%endif

%if %{with_tools}
%files -n %{name}-tools -f cpupower.lang
%{_bindir}/cpupower
%{_datadir}/bash-completion/completions/cpupower
%ifarch x86_64
%{_bindir}/centrino-decode
%{_bindir}/powernow-k8-decode
%endif
%{_mandir}/man[1-8]/cpupower*
%ifarch x86_64
%{_bindir}/x86_energy_perf_policy
%{_mandir}/man8/x86_energy_perf_policy*
%{_bindir}/turbostat
%{_mandir}/man8/turbostat*
%{_bindir}/intel-speed-select
%endif
%{_bindir}/tmon
%{_bindir}/iio_event_monitor
%{_bindir}/iio_generic_buffer
%{_bindir}/lsiio
%{_bindir}/lsgpio
%{_bindir}/gpio-hammer
%{_bindir}/gpio-event-mon
%{_bindir}/gpio-watch
%{_mandir}/man1/kvm_stat*
%{_bindir}/kvm_stat
%{_unitdir}/kvm_stat.service
%config(noreplace) %{_sysconfdir}/logrotate.d/kvm_stat
%{_bindir}/page_owner_sort
%{_bindir}/slabinfo

%files -n %{name}-tools-libs
%{_libdir}/libcpupower.so.1
%{_libdir}/libcpupower.so.1.0.1

%files -n %{name}-tools-libs-devel
%{_includedir}/cpufreq.h
%{_includedir}/cpuidle.h
%{_includedir}/powercap.h
%{_libdir}/libcpupower.so

%files -n rtla
%{_bindir}/rtla
%{_bindir}/hwnoise
%{_bindir}/osnoise
%{_bindir}/timerlat
%{_mandir}/man1/rtla-hwnoise.1.gz
%{_mandir}/man1/rtla-osnoise-hist.1.gz
%{_mandir}/man1/rtla-osnoise-top.1.gz
%{_mandir}/man1/rtla-osnoise.1.gz
%{_mandir}/man1/rtla-timerlat-hist.1.gz
%{_mandir}/man1/rtla-timerlat-top.1.gz
%{_mandir}/man1/rtla-timerlat.1.gz
%{_mandir}/man1/rtla.1.gz

%files -n rv
%{_bindir}/rv
%{_mandir}/man1/rv-list.1.gz
%{_mandir}/man1/rv-mon-wip.1.gz
%{_mandir}/man1/rv-mon-wwnr.1.gz
%{_mandir}/man1/rv-mon.1.gz
%{_mandir}/man1/rv.1.gz
%{_mandir}/man1/rv-mon-sched.1.gz

# with_tools
%endif

# Empty meta-package.
%ifarch x86_64 || aarch64
%files
%endif

#
# This macro defines the %%files sections for a kernel-ml package
# and its devel package.
#	%%kernel_ml_variant_files [-k vmlinux] <use_vdso> <condition> <subpackage>
#
%define kernel_ml_variant_files(k:) \
%if %{2}\
%{expand:%%files -f %{name}-%{?3:%{3}-}core.list %{?1:-f %{name}-%{?3:%{3}-}ldsoconf.list} %{?3:%{3}-}core}\
%{!?_licensedir:%global license %%doc}\
%license linux-%{KVERREL}/COPYING-%{version}-%{release}\
/lib/modules/%{KVERREL}%{?3:+%{3}}/%{?-k:%{-k*}}%{!?-k:vmlinuz}\
%ghost /boot/%{?-k:%{-k*}}%{!?-k:vmlinuz}-%{KVERREL}%{?3:+%{3}}\
/lib/modules/%{KVERREL}%{?3:+%{3}}/.vmlinuz.hmac \
%ghost /boot/.vmlinuz-%{KVERREL}%{?3:+%{3}}.hmac \
%ifarch aarch64\
/lib/modules/%{KVERREL}%{?3:+%{3}}/dtb \
%ghost /boot/dtb-%{KVERREL}%{?3:+%{3}} \
%endif\
%attr(0600, root, root) /lib/modules/%{KVERREL}%{?3:+%{3}}/System.map\
%ghost %attr(0600, root, root) /boot/System.map-%{KVERREL}%{?3:+%{3}}\
/lib/modules/%{KVERREL}%{?3:+%{3}}/symvers.gz\
/lib/modules/%{KVERREL}%{?3:+%{3}}/config\
%ghost %attr(0600, root, root) /boot/symvers-%{KVERREL}%{?3:+%{3}}.gz\
%ghost %attr(0600, root, root) /boot/initramfs-%{KVERREL}%{?3:+%{3}}.img\
%ghost %attr(0644, root, root) /boot/config-%{KVERREL}%{?3:+%{3}}\
%dir /lib/modules\
%dir /lib/modules/%{KVERREL}%{?3:+%{3}}\
%dir /lib/modules/%{KVERREL}%{?3:+%{3}}/kernel\
/lib/modules/%{KVERREL}%{?3:+%{3}}/build\
/lib/modules/%{KVERREL}%{?3:+%{3}}/source\
/lib/modules/%{KVERREL}%{?3:+%{3}}/updates\
/lib/modules/%{KVERREL}%{?3:+%{3}}/weak-updates\
/lib/modules/%{KVERREL}%{?3:+%{3}}/systemtap\
%if %{1}\
/lib/modules/%{KVERREL}%{?3:+%{3}}/vdso\
%endif\
/lib/modules/%{KVERREL}%{?3:+%{3}}/modules.*\
%{expand:%%files -f %{name}-%{?3:%{3}-}modules.list %{?3:%{3}-}modules}\
%{expand:%%files %{?3:%{3}-}devel}\
%defverify(not mtime)\
/usr/src/kernels/%{KVERREL}%{?3:+%{3}}\
%{expand:%%files %{?3:%{3}-}devel-matched}\
%{expand:%%files -f %{name}-%{?3:%{3}-}modules-extra.list %{?3:%{3}-}modules-extra}\
%config(noreplace) /etc/modprobe.d/*-blacklist.conf\
%if %{?3:1} %{!?3:0}\
%{expand:%%files %{3}}\
%endif\
%endif\
%{nil}

%kernel_ml_variant_files %{_use_vdso} %{with_std}

%changelog
* Wed Dec 24 2025 Akemi Yagi <toracat@elrepo.org> - 6.18.2-2
- Hyper-V related kernel optioned enabled
  [https://elrepo.org/bugs/view.php?id=1577]

