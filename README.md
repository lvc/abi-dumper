ABI Dumper 1.2
==============

ABI Dumper — a tool to dump ABI of an ELF object containing DWARF debug info.

Contents
--------

1. [ About                 ](#about)
2. [ Install               ](#install)
3. [ Usage                 ](#usage)
4. [ Filter public ABI     ](#filter-public-abi)
5. [ Check for ABI changes ](#check-for-abi-changes)

About
-----

The tool is intended to be used with ABI Compliance Checker tool for tracking
ABI changes of a C/C++ library or kernel module: https://github.com/lvc/abi-compliance-checker

The tool is developed by Andrey Ponomarenko.

Install
-------

    sudo make install prefix=/usr

###### Requires

* Perl 5
* Elfutils (eu-readelf)
* GNU Binutils
* Universal Ctags (https://github.com/universal-ctags/ctags)
* Vtable Dumper >= 1.1 (https://github.com/lvc/vtable-dumper)
* ABI Compliance Checker >= 2.2 (https://github.com/lvc/abi-compliance-checker)
* GCC C++

Usage
-----

Input objects should be compiled with `-g -Og` additional options to contain DWARF debug info.

    abi-dumper libTest.so -o ABI.dump
    abi-dumper Module.ko.debug

###### Examples

    abi-dumper lib/libssh.so.3
    abi-dumper drm/nouveau/nouveau.ko.debug

###### Docker

You can try Docker image if the tool is not packaged for your Linux distribution (example for Harfbuzz):

    FROM ebraminio/abi-dumper
    RUN apt update && \
        apt install -y ragel cpanminus && \
        git clone https://github.com/harfbuzz/harfbuzz && cd harfbuzz && \
            CFLAGS="-Og -g" CXXFLAGS="-Og -g" ./autogen.sh && make && cd .. && \
        abi-dumper `find . -name 'libharfbuzz.so.0.*'` && \
        cpanm JSON && \
        perl -le 'use JSON; print to_json(do shift, {canonical => 1, pretty => 1});' ./ABI.dump > ABI.json

###### Adv. usage

  For advanced usage, see output of `--help` option.

Filter public ABI
-----------------

    abi-dumper libTest.so -public-headers PATH

PATH — path to the install tree of a library.

Check for ABI changes
---------------------

    abi-dumper libTest.so.0 -o ABIv0.dump
    abi-dumper libTest.so.1 -o ABIv1.dump
    abi-compliance-checker -l libTest -old ABIv0.dump -new ABIv1.dump
