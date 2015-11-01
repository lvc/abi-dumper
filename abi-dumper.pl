#!/usr/bin/perl
###########################################################################
# ABI Dumper 0.99.12
# Dump ABI of an ELF object containing DWARF debug info
#
# Copyright (C) 2013-2015 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  Linux
#
# REQUIREMENTS
# ============
#  Perl 5 (5.8 or newer)
#  Elfutils (eu-readelf)
#  Vtable-Dumper (1.1 or newer)
#
# SUGGESTS
# ========
#  Ctags (5.8 or newer)
#
# COMPATIBILITY
# =============
#  ABI Compliance Checker >= 1.99.14
#
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License or the GNU Lesser
# General Public License as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# and the GNU Lesser General Public License along with this program.
# If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case", "permute");
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use Cwd qw(abs_path cwd realpath);
use Storable qw(dclone);
use Data::Dumper;

my $TOOL_VERSION = "0.99.12";
my $ABI_DUMP_VERSION = "3.2";
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);

my $VTABLE_DUMPER = "vtable-dumper";
my $VTABLE_DUMPER_VERSION = "1.0";

my $LOCALE = "LANG=C.UTF-8";
my $EU_READELF = "eu-readelf";
my $EU_READELF_L = $LOCALE." ".$EU_READELF;
my $CTAGS = "ctags";

my ($Help, $ShowVersion, $DumpVersion, $OutputDump, $SortDump, $StdOut,
$TargetVersion, $ExtraInfo, $FullDump, $AllTypes, $AllSymbols, $BinOnly,
$SkipCxx, $Loud, $AddrToName, $DumpStatic, $Compare, $AltDebugInfo,
$AddDirs, $VTDumperPath, $SymbolsListPath, $PublicHeadersPath,
$IgnoreTagsPath);

my $CmdName = getFilename($0);

my %ERROR_CODE = (
    "Success"=>0,
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Cannot find a module
    "Module_Error"=>9,
    # No debug-info
    "No_DWARF"=>10,
    # Invalid debug-info
    "Invalid_DWARF"=>11
);

my $ShortUsage = "ABI Dumper $TOOL_VERSION
Dump ABI of an ELF object containing DWARF debug info
Copyright (C) 2015 Andrey Ponomarenko's ABI Laboratory
License: GNU LGPL or GNU GPL

Usage: $CmdName [options] [object]
Example:
  $CmdName libTest.so -o ABI.dump
  $CmdName Module.ko.debug -o ABI.dump

More info: $CmdName --help\n";

if($#ARGV==-1)
{
    printMsg("INFO", $ShortUsage);
    exit(0);
}

GetOptions("h|help!" => \$Help,
  "v|version!" => \$ShowVersion,
  "dumpversion!" => \$DumpVersion,
# general options
  "o|output|dump-path=s" => \$OutputDump,
  "sort!" => \$SortDump,
  "stdout!" => \$StdOut,
  "loud!" => \$Loud,
  "vnum|lver|lv=s" => \$TargetVersion,
  "extra-info=s" => \$ExtraInfo,
  "bin-only!" => \$BinOnly,
  "all-types!" => \$AllTypes,
  "all-symbols!" => \$AllSymbols,
  "symbols-list=s" => \$SymbolsListPath,
  "skip-cxx!" => \$SkipCxx,
  "all!" => \$FullDump,
  "dump-static!" => \$DumpStatic,
  "compare!" => \$Compare,
  "alt=s" => \$AltDebugInfo,
  "dir!" => \$AddDirs,
  "vt-dumper=s" => \$VTDumperPath,
  "public-headers=s" => \$PublicHeadersPath,
  "ignore-tags=s" => \$IgnoreTagsPath,
# internal options
  "addr2name!" => \$AddrToName
) or ERR_MESSAGE();

sub ERR_MESSAGE()
{
    printMsg("INFO", "\n".$ShortUsage);
    exit($ERROR_CODE{"Error"});
}

my $HelpMessage="
NAME:
  ABI Dumper ($CmdName)
  Dump ABI of an ELF object containing DWARF debug info

DESCRIPTION:
  ABI Dumper is a tool for dumping ABI information of an ELF object
  containing DWARF debug info.
  
  The tool is intended to be used with ABI Compliance Checker tool for
  tracking ABI changes of a C/C++ library or kernel module.

  This tool is free software: you can redistribute it and/or modify it
  under the terms of the GNU LGPL or GNU GPL.

USAGE:
  $CmdName [options] [object]

EXAMPLES:
  $CmdName libTest.so -o ABI.dump
  $CmdName Module.ko.debug -o ABI.dump

INFORMATION OPTIONS:
  -h|-help
      Print this help.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -o|-output PATH
      Path to the output ABI dump file.
      Default: ./ABI.dump
      
  -sort
      Sort data in ABI dump.
      
  -stdout
      Print ABI dump to stdout.
      
  -loud
      Print all warnings.
      
  -vnum NUM
      Set version of the library to NUM.
      
  -extra-info DIR
      Dump extra analysis info to DIR.
      
  -bin-only
      Do not dump information about inline functions,
      pure virtual functions and non-exported global data.
      
  -all-types
      Dump unused data types.
      
  -all-symbols
      Dump symbols not exported by the object.
      
  -symbols-list PATH
      Specify a file with a list of symbols that should be dumped.
      
  -skip-cxx
      Do not dump stdc++ and gnu c++ symbols.
      
  -all
      Equal to: -all-types -all-symbols.
      
  -dump-static
      Dump static (local) symbols.
      
  -compare OLD.dump NEW.dump
      Show added/removed symbols between two ABI dumps.
      
  -alt PATH
      Path to the alternate debug info (Fedora). It is
      detected automatically from gnu_debugaltlink section
      of the input object if not specified.
      
  -dir
      Show full paths of source files.
  
  -vt-dumper PATH
      Path to the vtable-dumper executable if it is installed
      to non-default location (not in PATH).
  
  -public-headers PATH
      Path to directory with public header files or to file with
      the list of header files. This option allows to filter out
      private symbols from the ABI dump.
  
  -ignore-tags PATH
      Path to ignore.tags file to help ctags tool to read
      symbols in header files.
";

sub HELP_MESSAGE() {
    printMsg("INFO", $HelpMessage);
}

my %Cache;

# Input
my %DWARF_Info;

# Alternate
my %ImportedUnit;
my %ImportedDecl;

# Dump
my %TypeUnit;
my %Post_Change;
my %UsedUnit;
my %UsedDecl;

# Output
my %SymbolInfo;
my %TypeInfo;

# Reader
my %TypeMember;
my %ArrayCount;
my %FuncParam;
my %TmplParam;
my %Inheritance;
my %NameSpace;
my %SpecElem;
my %OrigElem;
my %ClassMethods;
my %TypeSpec;
my %ClassChild;

my %MergedTypes;
my %LocalType;

my %SourceFile;
my %SourceFile_Alt;
my %DebugLoc;
my %TName_Tid;
my %TName_Tids;
my %RegName;

my $STDCXX_TARGET = 0;
my $GLOBAL_ID = 0;
my %ANON_TYPE_WARN = ();

my %Mangled_ID;
my %Checked_Spec;
my %SelectedSymbols;

my %TypeType = (
    "class_type"=>"Class",
    "structure_type"=>"Struct",
    "union_type"=>"Union",
    "enumeration_type"=>"Enum",
    "array_type"=>"Array",
    "base_type"=>"Intrinsic",
    "const_type"=>"Const",
    "pointer_type"=>"Pointer",
    "reference_type"=>"Ref",
    "rvalue_reference_type"=>"RvalueRef",
    "volatile_type"=>"Volatile",
    "typedef"=>"Typedef",
    "ptr_to_member_type"=>"FieldPtr",
    "string_type"=>"String"
);

my %Qual = (
    "Pointer"=>"*",
    "Ref"=>"&",
    "RvalueRef"=>"&&",
    "Volatile"=>"volatile",
    "Const"=>"const"
);

my %ConstSuffix = (
    "unsigned int" => "u",
    "unsigned long" => "ul",
    "unsigned long long" => "ull",
    "long" => "l",
    "long long" => "ll"
);

my $HEADER_EXT = "h|hh|hp|hxx|hpp|h\\+\\+|tcc";
my $SRC_EXT = "c|cpp|cxx|c\\+\\+";

# Other
my %NestedNameSpaces;
my $TargetName;
my %HeadersInfo;
my %SourcesInfo;
my %SymVer;
my %UsedType;

# ELF
my %Library_Symbol;
my %Library_UndefSymbol;
my %Library_Needed;
my %SymbolTable;

# VTables
my %VirtualTable;

# Env
my $SYS_ARCH;
my $SYS_WORD;
my $SYS_GCCV;
my $SYS_COMP;
my $LIB_LANG;
my $OBJ_LANG;

# Errors
my $InvalidDebugLoc;

# Public Headers
my %SymbolToHeader;
my %PublicHeader;
my $PublicSymbols_Detected;

# Filter
my %SymbolsList;

sub printMsg($$)
{
    my ($Type, $Msg) = @_;
    if($Type!~/\AINFO/) {
        $Msg = $Type.": ".$Msg;
    }
    if($Type!~/_C\Z/) {
        $Msg .= "\n";
    }
    if($Type eq "ERROR"
    or $Type eq "WARNING") {
        print STDERR $Msg;
    }
    else {
        print $Msg;
    }
}

sub exitStatus($$)
{
    my ($Code, $Msg) = @_;
    printMsg("ERROR", $Msg);
    exit($ERROR_CODE{$Code});
}

sub cmpVersions($$)
{ # compare two versions in dotted-numeric format
    my ($V1, $V2) = @_;
    return 0 if($V1 eq $V2);
    return undef if($V1!~/\A\d+[\.\d+]*\Z/);
    return undef if($V2!~/\A\d+[\.\d+]*\Z/);
    my @V1Parts = split(/\./, $V1);
    my @V2Parts = split(/\./, $V2);
    for (my $i = 0; $i <= $#V1Parts && $i <= $#V2Parts; $i++) {
        return -1 if(int($V1Parts[$i]) < int($V2Parts[$i]));
        return 1 if(int($V1Parts[$i]) > int($V2Parts[$i]));
    }
    return -1 if($#V1Parts < $#V2Parts);
    return 1 if($#V1Parts > $#V2Parts);
    return 0;
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = getDirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open(FILE, $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    return $Content;
}

sub getFilename($)
{ # much faster than basename() from File::Basename module
    if($_[0] and $_[0]=~/([^\/\\]+)[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub getDirname($)
{ # much faster than dirname() from File::Basename module
    if($_[0] and $_[0]=~/\A(.*?)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub check_Cmd($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    if(defined $Cache{"check_Cmd"}{$Cmd}) {
        return $Cache{"check_Cmd"}{$Cmd};
    }
    
    if(-x $Cmd)
    { # relative or absolute path
        return ($Cache{"check_Cmd"}{$Cmd} = 1);
    }
    
    foreach my $Path (sort {length($a)<=>length($b)} split(/:/, $ENV{"PATH"}))
    {
        if(-x $Path."/".$Cmd) {
            return ($Cache{"check_Cmd"}{$Cmd} = 1);
        }
    }
    return ($Cache{"check_Cmd"}{$Cmd} = 0);
}

my %ELF_BIND = map {$_=>1} (
    "WEAK",
    "GLOBAL",
    "LOCAL"
);

my %ELF_TYPE = map {$_=>1} (
    "FUNC",
    "IFUNC",
    "GNU_IFUNC",
    "TLS",
    "OBJECT",
    "COMMON"
);

my %ELF_VIS = map {$_=>1} (
    "DEFAULT",
    "PROTECTED"
);

sub readline_ELF($)
{ # read the line of 'eu-readelf' output corresponding to the symbol
    my @Info = split(/\s+/, $_[0]);
    #  Num:   Value      Size Type   Bind   Vis       Ndx  Name
    #  3629:  000b09c0   32   FUNC   GLOBAL DEFAULT   13   _ZNSt12__basic_fileIcED1Ev@@GLIBCXX_3.4
    #  135:   00000000    0   FUNC   GLOBAL DEFAULT   UNDEF  av_image_fill_pointers@LIBAVUTIL_52 (3)
    shift(@Info) if($Info[0] eq ""); # spaces
    shift(@Info); # num
    
    if($#Info==7)
    { # UNDEF SYMBOL (N)
        if($Info[7]=~/\(\d+\)/) {
            pop(@Info);
        }
    }
    
    if($#Info!=6)
    { # other lines
        return ();
    }
    return () if(not defined $ELF_TYPE{$Info[2]} and $Info[5] ne "UNDEF");
    return () if(not defined $ELF_BIND{$Info[3]});
    return () if(not defined $ELF_VIS{$Info[4]});
    if($Info[5] eq "ABS" and $Info[0]=~/\A0+\Z/)
    { # 1272: 00000000     0 OBJECT  GLOBAL DEFAULT  ABS CXXABI_1.3
        return ();
    }
    if(index($Info[2], "0x") == 0)
    { # size == 0x3d158
        $Info[2] = hex($Info[2]);
    }
    return @Info;
}

sub read_Symbols($)
{
    my $Lib_Path = $_[0];
    my $Lib_Name = getFilename($Lib_Path);
    
    my $Dynamic = ($Lib_Name=~/\.so(\.|\Z)/);
    my $Dbg = ($Lib_Name=~/\.debug\Z/);
    
    if(not check_Cmd($EU_READELF)) {
        exitStatus("Not_Found", "can't find \"eu-readelf\"");
    }
    
    my %SectionInfo;
    
    my $Cmd = $EU_READELF_L." -S \"$Lib_Path\" 2>\"$TMP_DIR/error\"";
    foreach (split(/\n/, `$Cmd`))
    {
        if(/\[\s*(\d+)\]\s+([\w\.]+)/)
        {
            $SectionInfo{$1} = $2;
        }
    }
    
    if($Dynamic)
    { # dynamic library specifics
        $Cmd = $EU_READELF_L." -d \"$Lib_Path\" 2>\"$TMP_DIR/error\"";
        foreach (split(/\n/, `$Cmd`))
        {
            if(/NEEDED.+\[([^\[\]]+)\]/)
            { # dependencies:
              # 0x00000001 (NEEDED) Shared library: [libc.so.6]
                $Library_Needed{$1} = 1;
            }
        }
    }
    
    my $ExtraPath = undef;
    
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraPath = $ExtraInfo."/elf-info";
    }
    
    $Cmd = $EU_READELF_L." -s \"$Lib_Path\" 2>\"$TMP_DIR/error\"";
    
    if($ExtraPath)
    { # debug mode
        # write to file
        system($Cmd." >\"$ExtraPath\"");
        open(LIB, $ExtraPath);
    }
    else
    { # write to pipe
        open(LIB, $Cmd." |");
    }
    
    my (%Symbol_Value, %Value_Symbol) = ();
    
    my $symtab = undef; # indicates that we are processing 'symtab' section of 'readelf' output
    while(<LIB>)
    {
        if($Dynamic and not $Dbg)
        { # dynamic library specifics
            if(defined $symtab)
            {
                if(index($_, "'.dynsym'")!=-1)
                { # dynamic table
                    $symtab = undef;
                }
                if(not $AllSymbols)
                { # do nothing with symtab
                    #next;
                }
            }
            elsif(index($_, "'.symtab'")!=-1)
            { # symbol table
                $symtab = 1;
            }
        }
        if(my ($Value, $Size, $Type, $Bind, $Vis, $Ndx, $Symbol) = readline_ELF($_))
        { # read ELF entry
            if(not $symtab)
            { # dynsym
                if(skipSymbol($Symbol)) {
                    next;
                }
                
                if($Ndx eq "UNDEF")
                { # ignore interfaces that are imported from somewhere else
                    $Library_UndefSymbol{$TargetName}{$Symbol} = 0;
                    next;
                }
                
                if($Bind ne "LOCAL") {
                    $Library_Symbol{$TargetName}{$Symbol} = ($Type eq "OBJECT")?-$Size:1;
                }
                
                $Symbol_Value{$Symbol} = $Value;
                $Value_Symbol{$Value}{$Symbol} = 1;
                
                if(defined $PublicHeadersPath)
                {
                    if(not defined $OBJ_LANG)
                    {
                        if(index($Symbol, "_Z")==0)
                        {
                            $OBJ_LANG = "C++";
                        }
                    }
                }
            }
            else
            {
                $Symbol_Value{$Symbol} = $Value;
                $Value_Symbol{$Value}{$Symbol} = 1;
            }
            
            if(not $symtab)
            {
                foreach ($SectionInfo{$Ndx}, "")
                {
                    my $Val = $Value;
                    
                    $SymbolTable{$_}{$Val}{$Symbol} = 1;
                    
                    if($Val=~s/\A[0]+//)
                    {
                        if($Val eq "") {
                            $Val = "0";
                        }
                        $SymbolTable{$_}{$Val}{$Symbol} = 1;
                    }
                }
            }
        }
    }
    close(LIB);
    
    if(not defined $Library_Symbol{$TargetName}) {
        return;
    }
    
    my %Found = ();
    foreach my $Symbol (sort keys(%Symbol_Value))
    {
        next if(index($Symbol,"\@")==-1);
        if(my $Value = $Symbol_Value{$Symbol})
        {
            foreach my $Symbol_SameValue (sort keys(%{$Value_Symbol{$Value}}))
            {
                if($Symbol_SameValue ne $Symbol
                and index($Symbol_SameValue,"\@")==-1)
                {
                    $SymVer{$Symbol_SameValue} = $Symbol;
                    $Found{$Symbol} = 1;
                    #last;
                }
            }
        }
    }
    
    # default
    foreach my $Symbol (sort keys(%Symbol_Value))
    {
        next if(defined $Found{$Symbol});
        next if(index($Symbol,"\@\@")==-1);
        
        if($Symbol=~/\A([^\@]*)\@\@/
        and not $SymVer{$1})
        {
            $SymVer{$1} = $Symbol;
            $Found{$Symbol} = 1;
        }
    }
    
    # non-default
    foreach my $Symbol (sort keys(%Symbol_Value))
    {
        next if(defined $Found{$Symbol});
        next if(index($Symbol,"\@")==-1);
        
        if($Symbol=~/\A([^\@]*)\@([^\@]*)/
        and not $SymVer{$1})
        {
            $SymVer{$1} = $Symbol;
            $Found{$Symbol} = 1;
        }
    }
    
    if(defined $PublicHeadersPath)
    {
        if(not defined $OBJ_LANG)
        {
            $OBJ_LANG = "C";
        }
    }
}

sub read_Alt_Info($)
{
    my $Path = $_[0];
    my $Name = getFilename($Path);
    
    if(not check_Cmd($EU_READELF)) {
        exitStatus("Not_Found", "can't find \"$EU_READELF\" command");
    }
    
    printMsg("INFO", "Reading alternate debug-info");
    
    my $ExtraPath = undef;
    
    # lines info
    if($ExtraInfo)
    {
        $ExtraPath = $ExtraInfo."/alt";
        mkpath($ExtraPath);
        $ExtraPath .= "/debug_line";
    }
    
    if($ExtraPath)
    {
        system($EU_READELF_L." -N --debug-dump=line \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open(SRC, $ExtraPath);
    }
    else {
        open(SRC, $EU_READELF_L." -N --debug-dump=line \"$Path\" 2>\"$TMP_DIR/error\" |");
    }
    
    my $DirTable_Def = undef;
    my %DirTable = ();
    
    while(<SRC>)
    {
        if(defined $AddDirs)
        {
            if(/Directory table/i)
            {
                $DirTable_Def = 1;
                next;
            }
            elsif(/File name table/i)
            {
                $DirTable_Def = undef;
                next;
            }
            
            if(defined $DirTable_Def)
            {
                if(/\A\s*(.+?)\Z/) {
                    $DirTable{keys(%DirTable)+1} = $1;
                }
            }
        }
        
        if(/(\d+)\s+(\d+)\s+\d+\s+\d+\s+([^ ]+)/)
        {
            my ($Num, $Dir, $File) = ($1, $2, $3);
            chomp($File);
            
            if(defined $AddDirs)
            {
                if(my $DName = $DirTable{$Dir})
                {
                    $File = $DName."/".$File;
                }
            }
            
            $SourceFile_Alt{0}{$Num} = $File;
        }
    }
    close(SRC);
    
    # debug info
    if($ExtraInfo)
    {
        $ExtraPath = $ExtraInfo."/alt";
        mkpath($ExtraPath);
        $ExtraPath .= "/debug_info";
    }
    
    if($ExtraPath)
    {
        system($EU_READELF_L." -N --debug-dump=info \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open(INFO, $ExtraPath);
    }
    else {
        open(INFO, $EU_READELF_L." -N --debug-dump=info \"$Path\" 2>\"$TMP_DIR/error\" |");
    }
    
    my $ID = undef;
    my $Num = 0;
    
    while(<INFO>)
    {
        if(index($_, "  ")==0)
        {
            if(defined $ID) {
                $ImportedUnit{$ID}{$Num++} = $_;
            }
        }
        elsif(index($_, " [")==0
        and /\A \[\s*(\w+?)\](\s+)(\w+)/)
        {
            if($3 eq "partial_unit")
            {
                $ID = $1;
                $Num = 0;
                $ImportedUnit{$ID}{0} = $_;
            }
            elsif(length($2)==2)
            { # not a partial_unit
                $ID = undef;
            }
            elsif(defined $ID)
            {
                $ImportedDecl{$1} = $ID;
                $ImportedUnit{$ID}{$Num++} = $_;
            }
        }
    }
}

sub read_DWARF_Info($)
{
    my $Path = $_[0];
    
    my $Dir = getDirname($Path);
    my $Name = getFilename($Path);
    
    if(not check_Cmd($EU_READELF)) {
        exitStatus("Not_Found", "can't find \"$EU_READELF\" command");
    }
    
    my $AddOpt = "";
    if(not defined $AddrToName)
    { # disable search of symbol names
        $AddOpt .= " -N";
    }
    
    my $Sect = `$EU_READELF_L -S \"$Path\" 2>\"$TMP_DIR/error\"`;
    
    if($Sect!~/\.z?debug_info/)
    { # No DWARF info
        if(my $DebugFile = getDebugFile($Path, "gnu_debuglink"))
        {
            my $DPath = $DebugFile;
            
            if(my $DDir = getDirname($Path))
            {
                $DPath = $DDir."/".$DPath;
            }
            
            printMsg("INFO", "Reading $DPath (gnu_debuglink)");
            
            return read_DWARF_Info($DPath);
        }
        return 0;
    }
    
    printMsg("INFO", "Reading debug-info");
    
    my $ExtraPath = undef;
    
    # ELF header
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraPath = $ExtraInfo."/elf-header";
    }
    
    if($ExtraPath)
    {
        system($EU_READELF_L." -h \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open(HEADER, $ExtraPath);
    }
    else {
        open(HEADER, $EU_READELF_L." -h \"$Path\" 2>\"$TMP_DIR/error\" |");
    }
    
    my %Header = ();
    while(<HEADER>)
    {
        if(/\A\s*([\w ]+?)\:\s*(.+?)\Z/) {
            $Header{$1} = $2;
        }
    }
    close(HEADER);
    
    $SYS_ARCH = $Header{"Machine"};
    
    if($SYS_ARCH=~/80\d86/
    or $SYS_ARCH=~/i\d86/)
    { # i386, i586, etc.
        $SYS_ARCH = "x86";
    }
    
    if($SYS_ARCH=~/amd64/i
    or $SYS_ARCH=~/x86\-64/i)
    { # amd64
        $SYS_ARCH = "x86_64";
    }
    
    init_Registers();
    
    # ELF sections
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraPath = $ExtraInfo."/elf-sections";
    }
    
    if($ExtraPath)
    {
        system($EU_READELF_L." -S \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open(HEADER, $ExtraPath);
    }
    
    # source info
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraPath = $ExtraInfo."/debug_line";
    }
    
    if($ExtraPath)
    {
        system($EU_READELF_L." $AddOpt --debug-dump=line \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open(SRC, $ExtraPath);
    }
    else {
        open(SRC, $EU_READELF_L." $AddOpt --debug-dump=line \"$Path\" 2>\"$TMP_DIR/error\" |");
    }
    
    my $Offset = undef;
    my $DirTable_Def = undef;
    my %DirTable = ();
    
    while(<SRC>)
    {
        if(defined $AddDirs)
        {
            if(/Directory table/i)
            {
                $DirTable_Def = 1;
                %DirTable = ();
                next;
            }
            elsif(/File name table/i)
            {
                $DirTable_Def = undef;
                next;
            }
            
            if(defined $DirTable_Def)
            {
                if(/\A\s*(.+?)\Z/) {
                    $DirTable{keys(%DirTable)+1} = $1;
                }
            }
        }
        
        if(/Table at offset (\w+)/i) {
            $Offset = $1;
        }
        elsif(defined $Offset
        and /(\d+)\s+(\d+)\s+\d+\s+\d+\s+([^ ]+)/)
        {
            my ($Num, $Dir, $File) = ($1, $2, $3);
            chomp($File);
            
            if(defined $AddDirs)
            {
                if(my $DName = $DirTable{$Dir})
                {
                    $File = $DName."/".$File;
                }
            }
            
            $SourceFile{$Offset}{$Num} = $File;
        }
    }
    close(SRC);
    
    # debug_loc
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraPath = $ExtraInfo."/debug_loc";
    }
    
    if($ExtraPath)
    {
        system($EU_READELF_L." $AddOpt --debug-dump=loc \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open(LOC, $ExtraPath);
    }
    else {
        open(LOC, $EU_READELF_L." $AddOpt --debug-dump=loc \"$Path\" 2>\"$TMP_DIR/error\" |");
    }
    
    while(<LOC>)
    {
        if(/\A \[\s*(\w+)\].*\[\s*\w+\]\s*(.+)\Z/) {
            $DebugLoc{$1} = $2;
        }
        elsif(/\A \[\s*(\w+)\]/) {
            $DebugLoc{$1} = "";
        }
    }
    close(LOC);
    
    # dwarf
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraPath = $ExtraInfo."/debug_info";
    }
    
    my $INFO_fh;
    
    if($Dir)
    { # to find ".dwz" directory (Fedora)
        chdir($Dir);
    }
    if($ExtraPath)
    {
        system($EU_READELF_L." $AddOpt --debug-dump=info \"$Name\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        open($INFO_fh, $ExtraPath);
    }
    else {
        open($INFO_fh, $EU_READELF_L." $AddOpt --debug-dump=info \"$Name\" 2>\"$TMP_DIR/error\" |");
    }
    chdir($ORIG_DIR);
    
    read_DWARF_Dump($INFO_fh, 1);
    
    close($INFO_fh);
    
    if(my $Err = readFile("$TMP_DIR/error"))
    { # eu-readelf: cannot get next DIE: invalid DWARF
        if($Err=~/invalid DWARF/i)
        {
            if($Loud) {
                printMsg("ERROR", $Err);
            }
            exitStatus("Invalid_DWARF", "invalid DWARF info");
        }
    }
    
    return 1;
}

sub getSource($)
{
    my $ID = $_[0];
    
    if(defined $DWARF_Info{$ID}{"decl_file"})
    {
        my $File = $DWARF_Info{$ID}{"decl_file"};
        my $Unit = $DWARF_Info{$ID}{"Unit"};
        
        my $Name = undef;
        
        if($ID>=0) {
            $Name = $SourceFile{$Unit}{$File};
        }
        else
        { # imported
            $Name = $SourceFile_Alt{0}{$File};
        }
        
        return $Name;
    }
    
    return undef;
}

sub read_DWARF_Dump($$)
{
    my ($FH, $Primary) = @_;
    
    my $TypeUnit_Sign = undef;
    my $TypeUnit_Offset = undef;
    my $Type_Offset = undef;
    
    my $Shift_Enabled = 1;
    my $ID_Shift = undef;
    
    my $CUnit = undef;
    
    my $Compressed = undef;
    
    if($AltDebugInfo) {
        $Compressed = 1;
    }
    
    my $ID = undef;
    my $Kind = undef;
    my $NS = undef;
    
    my $MAX_ID = undef;
    
    my %Shift = map {$_=>1} (
        "specification",
        "type",
        "sibling",
        "object_pointer",
        "containing_type",
        "abstract_origin",
        "import",
        "signature"
    );
    
    my $Line = undef;
    my $Import = undef;
    my $Import_Num = 0;
    
    my %SkipNode = (
        "imported_declaration" => 1,
        "imported_module" => 1
    );
    
    my %SkipAttr = (
        "high_pc" => 1,
        "frame_base" => 1,
        "encoding" => 1
    );
    
    my %MarkByUnit = (
        "member" => 1,
        "subprogram" => 1,
        "variable" => 1
    );
    
    my $Lexical_Block = undef;
    my $Inlined_Block = undef;
    my $Subprogram_Block = undef;
    my $Skip_Block = undef;
    
    while(($Import and $Line = $ImportedUnit{$Import}{$Import_Num}) or $Line = <$FH>)
    {
        if($Import)
        {
            if(not defined $ImportedUnit{$Import}{$Import_Num})
            {
                $Import_Num = 0;
                delete($ImportedUnit{$Import});
                $Import = undef;
            }
            
            $Import_Num+=1;
        }
        
        if(defined $ID and $Line=~/\A\s*(\w+)\s*(.+?)\s*\Z/)
        {
            if(defined $Skip_Block) {
                next;
            }
            
            my $Attr = $1;
            my $Val = $2;
            
            if(index($Val, "flag_present")!=-1)
            { # Fedora
                $Val = "Yes";
            }
            
            if(defined $Compressed)
            {
                if($Kind eq "imported_unit")
                {
                    if($Attr eq "import")
                    {
                        if($Val=~/\(GNU_ref_alt\)\s*\[\s*(\w+?)\]/)
                        {
                            if(defined $ImportedUnit{$1})
                            {
                                $Import = $1;
                                $Import_Num = 0;
                                $UsedUnit{$Import} = 1;
                            }
                        }
                    }
                }
            }
            
            if($Kind eq "member")
            {
                if($Attr eq "data_member_location")
                {
                    delete($DWARF_Info{$ID}{"Unit"});
                }
            }
            
            if($Attr eq "sibling")
            {
                if($Kind ne "structure_type")
                {
                    next;
                }
            }
            elsif($Attr eq "Type")
            {
                if($Line=~/Type\s+signature:\s*0x(\w+)/) {
                    $TypeUnit_Sign = $1;
                }
                if($Line=~/Type\s+offset:\s*0x(\w+)/) {
                    $Type_Offset = hex($1);
                }
                if($Line=~/Type\s+unit\s+at\s+offset\s+(\d+)/) {
                    $TypeUnit_Offset = $1;
                }
                next;
            }
            elsif(defined $SkipAttr{$Attr})
            { # unused
                next;
            }
            
            if($Val=~/\A\s*\(([^()]*)\)\s*\[\s*(\w+)\]\s*\Z/)
            { # ref4, ref_udata, ref_addr, etc.
                $Val = hex($2);
                
                if($1 eq "GNU_ref_alt")
                {
                    $Val = -$Val;
                    $UsedDecl{$2} = 1;
                }
            }
            elsif($Attr eq "name")
            {
                $Val=~s/\A\([^()]*\)\s*\"(.*)\"\Z/$1/;
            }
            elsif(index($Attr, "linkage_name")!=-1)
            {
                $Val=~s/\A\([^()]*\)\s*\"(.*)\"\Z/$1/;
                $Attr = "linkage_name";
            }
            elsif(index($Attr, "location")!=-1)
            {
                if($Val=~/\)\s*\Z/)
                { # value on the next line
                    my $NL = "";
                    
                    if($Import) {
                        $NL = $ImportedUnit{$Import}{$Import_Num}
                    }
                    else {
                        $NL = <$FH>;
                    }
                    
                    $Val .= $NL;
                }
                
                if($Val=~/\A\(\w+\)\s*(-?)(\w+)\Z/)
                { # (data1) 1c
                    $Val = hex($2);
                    if($1) {
                        $Val = -$Val;
                    }
                }
                else
                {
                    if($Val=~/ (-?\d+)\Z/) {
                        $Val = $1;
                    }
                    else
                    {
                        if($Attr eq "location"
                        and $Kind eq "formal_parameter")
                        {
                            if($Val=~/location list\s+\[\s*(\w+)\]\Z/)
                            {
                                $Attr = "location_list";
                                $Val = $1;
                            }
                            elsif($Val=~/ reg(\d+)\Z/)
                            {
                                $Attr = "register";
                                $Val = $1;
                            }
                        }
                    }
                }
            }
            elsif($Attr eq "accessibility")
            {
                $Val=~s/\A\(.+?\)\s*//;
                $Val=~s/\s*\(.+?\)\Z//;
                
                # NOTE: members: private by default
            }
            else
            {
                $Val=~s/\A\(\w+\)\s*//;
                
                if(substr($Val, 0, 1) eq "{"
                and $Val=~/{(.+)}/)
                { # {ID}
                    $Val = $1;
                    $Post_Change{$ID} = 1;
                }
            }
            
            if(defined $Shift_Enabled and $ID_Shift)
            {
                if(defined $Shift{$Attr}
                and not $Post_Change{$ID}) {
                    $Val += $ID_Shift;
                }
                
                # $DWARF_Info{$ID}{"rID"} = $ID-$ID_Shift;
            }
            
            if($Import or not $Primary)
            {
                if(defined $Shift{$Attr})
                {
                    $Val = -$Val;
                }
            }
            
            $DWARF_Info{$ID}{$Attr} = "$Val";
            
            if($Kind eq "compile_unit")
            {
                if($Attr eq "stmt_list") {
                    $CUnit = $Val;
                }
                
                if(not defined $LIB_LANG)
                {
                    if($Attr eq "language")
                    {
                        if(index($Val, "Assembler")==-1)
                        {
                            $Val=~s/\s*\(.+?\)\Z//;
                            
                            if($Val=~/C\d/i) {
                                $LIB_LANG = "C";
                            }
                            elsif($Val=~/C\+\+|C_plus_plus/i) {
                                $LIB_LANG = "C++";
                            }
                            else {
                                $LIB_LANG = $Val;
                            }
                        }
                    }
                }
                
                if(not defined $SYS_COMP and not defined $SYS_GCCV)
                {
                    if($Attr eq "producer")
                    {
                        if(index($Val, "GNU AS")==-1)
                        {
                            $Val=~s/\A\"//;
                            $Val=~s/\"\Z//;
                            
                            if($Val=~/GNU\s+(C|C\+\+)\s+(.+)\Z/)
                            {
                                $SYS_GCCV = $2;
                                if($SYS_GCCV=~/\A(\d+\.\d+)(\.\d+|)/)
                                { # 4.6.1 20110627 (Mandriva)
                                    $SYS_GCCV = $1.$2;
                                }
                                
                                if($Val=~/(\A| )(\-O[0-3])( |\Z)/) {
                                    printMsg("WARNING", "incompatible build option detected: $2");
                                }
                            }
                            else {
                                $SYS_COMP = $Val;
                            }
                        }
                    }
                }
            }
            elsif($Kind eq "type_unit")
            {
                if($Attr eq "stmt_list") {
                    $CUnit = $Val;
                }
            }
            elsif($Kind eq "partial_unit" and not $Import)
            { # support for dwz
                if($Attr eq "stmt_list") {
                    $CUnit = $Val;
                }
            }
        }
        elsif($Line=~/\A \[\s*(\w+)\](\s*)(\w+)/)
        {
            $ID = hex($1);
            $NS = length($2);
            $Kind = $3;
            
            if(not defined $Compressed)
            {
                if($Kind eq "partial_unit" or $Kind eq "type_unit")
                { # compressed debug_info
                    $Compressed = 1;
                }
            }
            
            if(not $Compressed)
            { # compile units can depend on each other in the compressed debug_info
              # so reading them all integrally by one call of read_ABI()
                if($Kind eq "compile_unit" and $CUnit)
                { # read the previous compile unit
                    complete_Dump($Primary);
                    read_ABI();
                    
                    if(not defined $Compressed)
                    { # normal debug_info
                        $Compressed = 0;
                    }
                }
            }
            
            $Skip_Block = undef;
            
            if(defined $SkipNode{$Kind})
            {
                $Skip_Block = 1;
                next;
            }
            
            if($Kind eq "lexical_block")
            {
                $Lexical_Block = $NS;
                $Skip_Block = 1;
                next;
            }
            else
            {
                if(defined $Lexical_Block)
                {
                    if($NS>$Lexical_Block)
                    {
                        $Skip_Block = 1;
                        next;
                    }
                    else
                    { # end of lexical block
                        $Lexical_Block = undef;
                    }
                }
            }
            
            if($Kind eq "inlined_subroutine")
            {
                $Inlined_Block = $NS;
                $Skip_Block = 1;
                next;
            }
            else
            {
                if(defined $Inlined_Block)
                {
                    if($NS>$Inlined_Block)
                    {
                        $Skip_Block = 1;
                        next;
                    }
                    else
                    { # end of inlined subroutine
                        $Inlined_Block = undef;
                    }
                }
            }
            
            if($Kind eq "subprogram")
            {
                $Subprogram_Block = $NS;
            }
            else
            {
                if(defined $Subprogram_Block)
                {
                    if($NS>$Subprogram_Block)
                    {
                        if($Kind eq "variable")
                        { # temp variables
                            $Skip_Block = 1;
                            next;
                        }
                    }
                    else
                    { # end of subprogram block
                        $Subprogram_Block = undef;
                    }
                }
            }
            
            if($Import or not $Primary)
            {
                $ID = -$ID;
            }
            
            if(defined $Shift_Enabled)
            {
                if($Kind eq "type_unit")
                {
                    if(not defined $ID_Shift)
                    {
                        if($ID_Shift<=$MAX_ID) {
                            $ID_Shift = $MAX_ID;
                        }
                        else {
                            $ID_Shift = 0;
                        }
                    }
                }
                
                if($ID_Shift) {
                    $ID += $ID_Shift;
                }
            }
            
            if(defined $TypeUnit_Sign)
            {
                if($Kind ne "type_unit"
                and $Kind ne "namespace")
                {
                    if($TypeUnit_Offset+$Type_Offset+$ID_Shift==$ID)
                    {
                        $TypeUnit{$TypeUnit_Sign} = "$ID";
                        $TypeUnit_Sign = undef;
                    }
                }
            }
            
            $DWARF_Info{$ID}{"Kind"} = $Kind;
            $DWARF_Info{$ID}{"NS"} = $NS;
            
            if(defined $CUnit)
            {
                if(defined $MarkByUnit{$Kind}
                or defined $TypeType{$Kind}) {
                    $DWARF_Info{$ID}{"Unit"} = $CUnit;
                }
            }
            
            if(not defined $ID_Shift) {
                $MAX_ID = $ID;
            }
        }
        elsif(not defined $SYS_WORD
        and $Line=~/Address\s*size:\s*(\d+)/i)
        {
            $SYS_WORD = $1;
        }
    }
    
    # read the last compile unit
    # or all units if debug_info is compressed
    complete_Dump($Primary);
    read_ABI();
}

sub read_Vtables($)
{
    my $Path = $_[0];
    
    my $Name = getFilename($Path);
    $Path = abs_path($Path);
    
    if(index($LIB_LANG, "C++")!=-1)
    {
        printMsg("INFO", "Reading v-tables");
        
        if(check_Cmd($VTABLE_DUMPER))
        {
            if(my $Version = `$VTABLE_DUMPER -dumpversion`)
            {
                if(cmpVersions($Version, $VTABLE_DUMPER_VERSION)<0)
                {
                    printMsg("ERROR", "the version of Vtable-Dumper should be $VTABLE_DUMPER_VERSION or newer");
                    return;
                }
            }
        }
        else
        {
            printMsg("ERROR", "cannot find \'$VTABLE_DUMPER\'");
            return;
        }
        
        my $ExtraPath = $TMP_DIR."/v-tables";
        
        if($ExtraInfo)
        {
            mkpath($ExtraInfo);
            $ExtraPath = $ExtraInfo."/v-tables";
        }
        
        system("$VTABLE_DUMPER -mangled -demangled \"$Path\" 2>\"$TMP_DIR/error\" >\"$ExtraPath\"");
        
        my $Content = readFile($ExtraPath);
        foreach my $ClassInfo (split(/\n\n\n/, $Content))
        {
            if($ClassInfo=~/\AVtable\s+for\s+(.+)\n((.|\n)+)\Z/i)
            {
                my ($CName, $VTable) = ($1, $2);
                my @Entries = split(/\n/, $VTable);
                
                foreach (1 .. $#Entries)
                {
                    my $Entry = $Entries[$_];
                    if($Entry=~/\A(\d+)\s+(.+)\Z/) {
                        $VirtualTable{$CName}{$1} = $2;
                    }
                }
            }
        }
    }
    
    if(keys(%VirtualTable))
    {
        foreach my $Tid (sort keys(%TypeInfo))
        {
            if($TypeInfo{$Tid}{"Type"}=~/\A(Struct|Class)\Z/)
            {
                my $TName = $TypeInfo{$Tid}{"Name"};
                $TName=~s/\bstruct //g;
                if(defined $VirtualTable{$TName})
                {
                    %{$TypeInfo{$Tid}{"VTable"}} = %{$VirtualTable{$TName}};
                }
            }
        }
    }
}

sub dump_ABI()
{
    printMsg("INFO", "Creating ABI dump");
    
    my %ABI = (
        "TypeInfo" => \%TypeInfo,
        "SymbolInfo" => \%SymbolInfo,
        "Symbols" => \%Library_Symbol,
        "UndefinedSymbols" => \%Library_UndefSymbol,
        "Needed" => \%Library_Needed,
        "SymbolVersion" => \%SymVer,
        "LibraryVersion" => $TargetVersion,
        "LibraryName" => $TargetName,
        "Language" => $LIB_LANG,
        "Headers" => \%HeadersInfo,
        "Sources" => \%SourcesInfo,
        "NameSpaces" => \%NestedNameSpaces,
        "Target" => "unix",
        "Arch" => $SYS_ARCH,
        "WordSize" => $SYS_WORD,
        "ABI_DUMP_VERSION" => $ABI_DUMP_VERSION,
        "ABI_DUMPER_VERSION" => $TOOL_VERSION,
    );
    
    if($SYS_GCCV) {
        $ABI{"GccVersion"} = $SYS_GCCV;
    }
    else {
        $ABI{"Compiler"} = $SYS_COMP;
    }
    
    if(defined $PublicHeadersPath) {
        $ABI{"PublicABI"} = "1";
    }
    
    my $ABI_DUMP = Dumper(\%ABI);
    
    if($StdOut)
    { # --stdout option
        print STDOUT $ABI_DUMP;
    }
    else
    {
        mkpath(getDirname($OutputDump));
        
        open(DUMP, ">", $OutputDump) || die ("can't open file \'$OutputDump\': $!\n");
        print DUMP $ABI_DUMP;
        close(DUMP);
        
        printMsg("INFO", "\nThe object ABI has been dumped to:\n  $OutputDump");
    }
}

sub unmangleString($)
{
    my $Str = $_[0];
    
    $Str=~s/\AN(.+)E\Z/$1/;
    while($Str=~s/\A(\d+)//)
    {
        if(length($Str)==$1) {
            last;
        }
        
        $Str = substr($Str, $1, length($Str) - $1);
    }
    
    return $Str;
}

sub init_ABI()
{
    # register "void" type
    %{$TypeInfo{"1"}} = (
        "Name"=>"void",
        "Type"=>"Intrinsic"
    );
    $TName_Tid{"Intrinsic"}{"void"} = "1";
    $TName_Tids{"Intrinsic"}{"void"}{"1"} = 1;
    $Cache{"getTypeInfo"}{"1"} = 1;
    
    # register "..." type
    %{$TypeInfo{"-1"}} = (
        "Name"=>"...",
        "Type"=>"Intrinsic"
    );
    $TName_Tid{"Intrinsic"}{"..."} = "-1";
    $TName_Tids{"Intrinsic"}{"..."}{"-1"} = 1;
    $Cache{"getTypeInfo"}{"-1"} = 1;
}

sub complete_Dump($)
{
    my $Primary = $_[0];
    
    foreach my $ID (keys(%Post_Change))
    {
        if(my $Type = $DWARF_Info{$ID}{"type"})
        {
            if(my $To = $TypeUnit{$Type}) {
                $DWARF_Info{$ID}{"type"} = $To;
            }
        }
        if(my $Signature = $DWARF_Info{$ID}{"signature"})
        {
            if(my $To = $TypeUnit{$Signature}) {
                $DWARF_Info{$ID}{"signature"} = $To;
            }
        }
    }
    
    %Post_Change = ();
    %TypeUnit = ();
    
    if($Primary)
    {
        my %AddUnits = ();
        
        foreach my $ID (keys(%UsedDecl))
        {
            if(my $U_ID = $ImportedDecl{$ID})
            {
                if(not $UsedUnit{$U_ID})
                {
                    $AddUnits{$U_ID} = 1;
                }
            }
        }
        
        if(keys(%AddUnits))
        {
            my $ADD_DUMP = "";
            
            foreach my $U_ID (sort {hex($a)<=>hex($b)} keys(%AddUnits))
            {
                foreach my $N (sort {int($a)<=>int($b)} keys(%{$ImportedUnit{$U_ID}}))
                {
                    $ADD_DUMP .= $ImportedUnit{$U_ID}{$N};
                }
            }
            
            my $AddUnit_F = $TMP_DIR."/add_unit.dump";
            
            writeFile($AddUnit_F, $ADD_DUMP);
            
            my $FH_add;
            open($FH_add, $AddUnit_F);
            read_DWARF_Dump($FH_add, 0);
            close($FH_add);
            
            unlink($AddUnit_F);
        }
    }
    
    %UsedUnit = ();
    %UsedDecl = ();
}

sub read_ABI()
{
    my %CurID = ();
    
    my @IDs = sort {int($a) <=> int($b)} keys(%DWARF_Info);
    
    if($AltDebugInfo) {
        @IDs = sort {$b>0 <=> $a>0} sort {abs(int($a)) <=> abs(int($b))} @IDs;
    }
    
    my $TPack = undef;
    my $PPack = undef;
    
    foreach my $ID (@IDs)
    {
        $ID = "$ID";
        
        my $Kind = $DWARF_Info{$ID}{"Kind"};
        my $NS = $DWARF_Info{$ID}{"NS"};
        my $Scope = $CurID{$NS-2};
        
        if($Kind eq "typedef")
        {
            if($DWARF_Info{$Scope}{"Kind"} eq "subprogram")
            {
                $NS = $DWARF_Info{$Scope}{"NS"};
                $Scope = $CurID{$NS-2};
            }
        }
        
        if($Kind ne "subprogram") {
            delete($DWARF_Info{$ID}{"NS"});
        }
        
        my $IsType = ($Kind=~/(struct|structure|class|union|enumeration|subroutine|array)_type/);
        
        if($IsType
        or $Kind eq "typedef"
        or $Kind eq "subprogram"
        or $Kind eq "variable"
        or $Kind eq "namespace")
        {
            if($Kind ne "variable"
            and $Kind ne "typedef")
            {
                $CurID{$NS} = $ID;
            }
            
            if($Scope)
            {
                $NameSpace{$ID} = $Scope;
                if($Kind eq "subprogram"
                or $Kind eq "variable")
                {
                    if($DWARF_Info{$Scope}{"Kind"}=~/class|struct/)
                    {
                        $ClassMethods{$Scope}{$ID} = 1;
                        if(my $Sp = $DWARF_Info{$Scope}{"specification"}) {
                            $ClassMethods{$Sp}{$ID} = 1;
                        }
                    }
                }
            }
            
            if(my $Spec = $DWARF_Info{$ID}{"specification"}) {
                $SpecElem{$Spec} = $ID;
            }
            
            if(my $Orig = $DWARF_Info{$ID}{"abstract_origin"}) {
                $OrigElem{$Orig} = $ID;
            }
            
            if($IsType)
            {
                if(not $DWARF_Info{$ID}{"name"}
                and $DWARF_Info{$ID}{"linkage_name"})
                {
                    $DWARF_Info{$ID}{"name"} = unmangleString($DWARF_Info{$ID}{"linkage_name"});
                    
                    # free memory
                    delete($DWARF_Info{$ID}{"linkage_name"});
                }
            }
        }
        elsif($Kind eq "member")
        {
            if($Scope)
            {
                $NameSpace{$ID} = $Scope;
                
                if($DWARF_Info{$Scope}{"Kind"}=~/class|struct/
                and not defined $DWARF_Info{$ID}{"data_member_location"})
                { # variable (global data)
                    next;
                }
            }
            
            $TypeMember{$Scope}{keys(%{$TypeMember{$Scope}})} = $ID;
        }
        elsif($Kind eq "enumerator")
        {
            $TypeMember{$Scope}{keys(%{$TypeMember{$Scope}})} = $ID;
        }
        elsif($Kind eq "inheritance")
        {
            my %In = ();
            $In{"id"} = $DWARF_Info{$ID}{"type"};
            
            if(my $Access = $DWARF_Info{$ID}{"accessibility"})
            {
                if($Access ne "public")
                { # default inheritance access in ABI dump is "public"
                    $In{"access"} = $Access;
                }
            }
            
            if(defined $DWARF_Info{$ID}{"virtuality"}) {
                $In{"virtual"} = 1;
            }
            $Inheritance{$Scope}{keys(%{$Inheritance{$Scope}})} = \%In;
            
            # free memory
            delete($DWARF_Info{$ID});
        }
        elsif($Kind eq "formal_parameter")
        {
            if(defined $PPack) {
                $FuncParam{$PPack}{keys(%{$FuncParam{$PPack}})} = $ID;
            }
            else {
                $FuncParam{$Scope}{keys(%{$FuncParam{$Scope}})} = $ID;
            }
        }
        elsif($Kind eq "unspecified_parameters")
        {
            $FuncParam{$Scope}{keys(%{$FuncParam{$Scope}})} = $ID;
            $DWARF_Info{$ID}{"type"} = "-1"; # "..."
        }
        elsif($Kind eq "subrange_type")
        {
            if((my $Bound = $DWARF_Info{$ID}{"upper_bound"}) ne "") {
                $ArrayCount{$Scope} = $Bound + 1;
            }
            
            # free memory
            delete($DWARF_Info{$ID});
        }
        elsif($Kind eq "template_type_parameter"
        or $Kind eq "template_value_parameter")
        {
            my %Info = ("type"=>$DWARF_Info{$ID}{"type"}, "key"=>$DWARF_Info{$ID}{"name"});
            
            if(defined $DWARF_Info{$ID}{"const_value"}) {
                $Info{"value"} = $DWARF_Info{$ID}{"const_value"};
            }
            
            if(defined $DWARF_Info{$ID}{"default_value"}) {
                $Info{"default"} = 1;
            }
            
            if(defined $TPack) {
                $TmplParam{$TPack}{keys(%{$TmplParam{$TPack}})} = \%Info;
            }
            else {
                $TmplParam{$Scope}{keys(%{$TmplParam{$Scope}})} = \%Info;
            }
        }
        elsif($Kind eq "GNU_template_parameter_pack") {
            $TPack = $Scope;
        }
        elsif($Kind eq "GNU_formal_parameter_pack") {
            $PPack = $Scope;
        }
        
        if($Kind ne "GNU_template_parameter_pack")
        {
            if(index($Kind, "template_")==-1) {
                $TPack = undef;
            }
        }
        
        if($Kind ne "GNU_formal_parameter_pack")
        {
            if($Kind ne "formal_parameter") {
                $PPack = undef;
            }
        }
        
    }
    
    my @IDs = sort {int($a) <=> int($b)} keys(%DWARF_Info);
    
    if($AltDebugInfo) {
        @IDs = sort {$b>0 <=> $a>0} sort {abs(int($a)) <=> abs(int($b))} @IDs;
    }
    
    foreach my $ID (@IDs)
    {
        if(my $Kind = $DWARF_Info{$ID}{"Kind"})
        {
            if(defined $TypeType{$Kind}) {
                getTypeInfo($ID);
            }
        }
    }
    
    foreach my $Tid (@IDs)
    {
        if(defined $TypeInfo{$Tid})
        {
            my $Type = $TypeInfo{$Tid}{"Type"};
            
            if(not defined $TypeInfo{$Tid}{"Memb"})
            {
                if($Type=~/Struct|Class|Union|Enum/)
                {
                    if(my $Signature = $DWARF_Info{$Tid}{"signature"})
                    {
                        if(defined $TypeInfo{$Signature})
                        {
                            foreach my $Attr (keys(%{$TypeInfo{$Signature}}))
                            {
                                if(not defined $TypeInfo{$Tid}{$Attr}) {
                                    $TypeInfo{$Tid}{$Attr} = $TypeInfo{$Signature}{$Attr};
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    # delete types info
    foreach (keys(%DWARF_Info))
    {
        if(my $Kind = $DWARF_Info{$_}{"Kind"})
        {
            if(defined $TypeType{$Kind}) {
                delete($DWARF_Info{$_});
            }
        }
    }
    
    foreach my $ID (sort {int($a) <=> int($b)} keys(%DWARF_Info))
    {
        if($ID<0)
        { # imported
            next;
        }
        
        if($DWARF_Info{$ID}{"Kind"} eq "subprogram"
        or $DWARF_Info{$ID}{"Kind"} eq "variable")
        {
            getSymbolInfo($ID);
        }
    }
    
    %DWARF_Info = ();
    
    # free memory
    %TypeMember = ();
    %ArrayCount = ();
    %FuncParam = ();
    %TmplParam = ();
    %Inheritance = ();
    %NameSpace = ();
    %SpecElem = ();
    %OrigElem = ();
    %ClassMethods = ();
    
    $Cache{"getTypeInfo"} = {"1"=>1, "-1"=>1};
}

sub complete_ABI()
{
    # types
    my %Incomplete = ();
    my %Incomplete_TN = ();
    
    my @IDs = sort {int($a) <=> int($b)} keys(%TypeInfo);
    
    if($AltDebugInfo) {
        @IDs = sort {$b>0 <=> $a>0} sort {abs(int($a)) <=> abs(int($b))} @IDs;
    }
    
    foreach my $Tid (@IDs)
    {
        my $Name = $TypeInfo{$Tid}{"Name"};
        my $Type = $TypeInfo{$Tid}{"Type"};
        
        if(not defined $SpecElem{$Tid}
        and not defined $Incomplete_TN{$Type}{$Name})
        {
            if(not defined $TypeInfo{$Tid}{"Size"})
            {
                if($Type=~/Struct|Class|Union|Enum/)
                {
                    $Incomplete{$Tid} = 1;
                }
            }
        }
        
        $Incomplete_TN{$Type}{$Name} = 1;
    }
    
    # free memory
    %Incomplete_TN = ();
    
    foreach my $Tid (sort {int($a) <=> int($b)} keys(%Incomplete))
    {
        my $Name = $TypeInfo{$Tid}{"Name"};
        my $Type = $TypeInfo{$Tid}{"Type"};
        
        my @Adv_IDs = sort {int($a) <=> int($b)} keys(%{$TName_Tids{$Type}{$Name}});
    
        if($AltDebugInfo) {
            @Adv_IDs = sort {$b>0 <=> $a>0} sort {abs(int($a)) <=> abs(int($b))} @Adv_IDs;
        }
        
        foreach my $Tid_Adv (@Adv_IDs)
        {
            if($Tid_Adv!=$Tid)
            {
                if(defined $SpecElem{$Tid_Adv}
                or defined $TypeInfo{$Tid_Adv}{"Size"})
                {
                    foreach my $Attr (keys(%{$TypeInfo{$Tid_Adv}}))
                    {
                        if(not defined $TypeInfo{$Tid}{$Attr})
                        {
                            if(ref($TypeInfo{$Tid_Adv}{$Attr}) eq "HASH") {
                                $TypeInfo{$Tid}{$Attr} = dclone($TypeInfo{$Tid_Adv}{$Attr});
                            }
                            else {
                                $TypeInfo{$Tid}{$Attr} = $TypeInfo{$Tid_Adv}{$Attr};
                            }
                            
                        }
                    }
                    last;
                }
            }
        }
    }
    
    # free memory
    %Incomplete = ();
    
    my %Delete = ();
    
    foreach my $Tid (sort {int($a) <=> int($b)} keys(%TypeInfo))
    {
        if(defined $TypeInfo{$Tid}
        and $TypeInfo{$Tid}{"Type"} eq "Typedef")
        {
            my $TN = $TypeInfo{$Tid}{"Name"};
            my $TL = $TypeInfo{$Tid}{"Line"};
            my $NS = $TypeInfo{$Tid}{"NameSpace"};
            
            if(my $BTid = $TypeInfo{$Tid}{"BaseType"})
            {
                if(defined $TypeInfo{$BTid}
                and $TypeInfo{$BTid}{"Name"}=~/\Aanon\-(\w+)\-/)
                {
                    %{$TypeInfo{$Tid}} = %{$TypeInfo{$BTid}};
                    $TypeInfo{$Tid}{"Name"} = $1." ".$TN;
                    $TypeInfo{$Tid}{"Line"} = $TL;
                    
                    my $Name = $TypeInfo{$Tid}{"Name"};
                    my $Type = $TypeInfo{$Tid}{"Type"};
                    
                    if(not defined $TName_Tid{$Type}{$Name}
                    or ($Tid>0 and $Tid<$TName_Tid{$Type}{$Name})
                    or ($Tid>0 and $TName_Tid{$Type}{$Name}<0)) {
                        $TName_Tid{$Type}{$Name} = $Tid;
                    }
                    $TName_Tids{$Type}{$Name}{$Tid} = 1;
                    
                    if($NS) {
                        $TypeInfo{$Tid}{"NameSpace"} = $NS;
                    }
                    $Delete{$BTid} = 1;
                }
            }
        }
    }
    
    foreach my $Tid (keys(%Delete))
    {
        my $TN = $TypeInfo{$Tid}{"Name"};
        my $TT = $TypeInfo{$Tid}{"Type"};
        
        delete($TName_Tid{$TT}{$TN});
        delete($TName_Tids{$TT}{$TN}{$Tid});
        
        if(my @IDs = sort {int($a) <=> int($b)} keys(%{$TName_Tids{$TT}{$TN}}))
        { # minimal ID
            $TName_Tid{$TT}{$TN} = $IDs[0];
        }
        
        delete($TypeInfo{$Tid});
    }
    
    # free memory
    %Delete = ();
    
    # symbols
    foreach my $ID (sort {int($a) <=> int($b)} keys(%SymbolInfo))
    {
        # add missed c-tors
        if($SymbolInfo{$ID}{"Constructor"})
        {
            if($SymbolInfo{$ID}{"MnglName"}=~/(C[1-2])([EI]).+/)
            {
                my ($K1, $K2) = ($1, $2);
                foreach ("C1", "C2")
                {
                    if($K1 ne $_)
                    {
                        my $Name = $SymbolInfo{$ID}{"MnglName"};
                        $Name=~s/$K1$K2/$_$K2/;
                        
                        if(not defined $Mangled_ID{$Name}) {
                            cloneSymbol($ID, $Name);
                        }
                    }
                }
            }
        }
        
        # add missed d-tors
        if($SymbolInfo{$ID}{"Destructor"})
        {
            if($SymbolInfo{$ID}{"MnglName"}=~/(D[0-2])([EI]).+/)
            {
                my ($K1, $K2) = ($1, $2);
                foreach ("D0", "D1", "D2")
                {
                    if($K1 ne $_)
                    {
                        my $Name = $SymbolInfo{$ID}{"MnglName"};
                        $Name=~s/$K1$K2/$_$K2/;
                        
                        if(not defined $Mangled_ID{$Name}) {
                            cloneSymbol($ID, $Name);
                        }
                    }
                }
            }
        }
    }
    
    foreach my $ID (sort {int($a) <=> int($b)} keys(%SymbolInfo))
    {
        my $Symbol = $SymbolInfo{$ID}{"MnglName"};
        
        if(not $Symbol) {
            $Symbol = $SymbolInfo{$ID}{"ShortName"};
        }
        
        if($LIB_LANG eq "C++")
        {
            if(not $SymbolInfo{$ID}{"MnglName"})
            {
                if($SymbolInfo{$ID}{"Artificial"}
                or index($SymbolInfo{$ID}{"ShortName"}, "~")==0)
                {
                    delete($SymbolInfo{$ID});
                    next;
                }
            }
        }
        
        if($SymbolInfo{$ID}{"Class"}
        and not $SymbolInfo{$ID}{"Data"}
        and not $SymbolInfo{$ID}{"Constructor"}
        and not $SymbolInfo{$ID}{"Destructor"}
        and not $SymbolInfo{$ID}{"Virt"}
        and not $SymbolInfo{$ID}{"PureVirt"})
        {
            if(not defined $SymbolInfo{$ID}{"Param"}
            or $SymbolInfo{$ID}{"Param"}{0}{"name"} ne "this")
            {
                $SymbolInfo{$ID}{"Static"} = 1;
            }
        }
        
        if(not $SymbolInfo{$ID}{"Return"})
        { # void
            if(not $SymbolInfo{$ID}{"Constructor"}
            and not $SymbolInfo{$ID}{"Destructor"})
            {
                $SymbolInfo{$ID}{"Return"} = "1";
            }
        }
        
        if(defined $SymbolInfo{$ID}{"Source"} and defined $SymbolInfo{$ID}{"SourceLine"})
        {
            if(not defined $SymbolInfo{$ID}{"Header"} and not defined $SymbolInfo{$ID}{"Line"})
            {
                $SymbolInfo{$ID}{"Line"} = $SymbolInfo{$ID}{"SourceLine"};
                delete($SymbolInfo{$ID}{"SourceLine"});
            }
        }
        
        my $S = selectSymbol($ID);
        
        if($S==0)
        {
            if(defined $AllSymbols)
            {
                if($SymbolInfo{$ID}{"External"})
                {
                    $S = 1;
                }
                else
                { # local
                    if(defined $DumpStatic) {
                        $S = 1;
                    }
                }
            }
        }
        
        if($S==0)
        {
            delete($SymbolInfo{$ID});
            next;
        }
        elsif(defined $PublicHeadersPath)
        {
            if(not selectPublic($Symbol, $ID)
            and (not defined $SymbolInfo{$ID}{"Alias"} or not selectPublic($SymbolInfo{$ID}{"Alias"}, $ID)))
            {
                delete($SymbolInfo{$ID});
                next;
            }
        }
        
        $SelectedSymbols{$ID} = $S;
        
        delete($SymbolInfo{$ID}{"External"});
    }
}

sub selectPublic($$)
{
    my ($Symbol, $ID) = @_;
    
    if(not defined $SymbolInfo{$ID}{"Header"}
    or not defined $PublicHeader{getFilename($SymbolInfo{$ID}{"Header"})})
    {
        if($OBJ_LANG eq "C")
        {
            if(not defined $SymbolToHeader{$Symbol})
            {
                return 0;
            }
            elsif(defined $SymbolInfo{$ID}{"Header"}
            and $SymbolInfo{$ID}{"Header"} ne $SymbolToHeader{$Symbol}
            and not defined $SymbolInfo{$ID}{"Alias"})
            {
                return 0;
            }
        }
        else {
            return 0;
        }
    }
    
    return 1;
}

sub cloneSymbol($$)
{
    my ($ID, $Symbol) = @_;
    
    my $nID = undef;
    if(not defined $SymbolInfo{$ID + 1}) {
        $nID = $ID + 1;
    }
    else {
        $nID = ++$GLOBAL_ID;
    }
    foreach my $Attr (keys(%{$SymbolInfo{$ID}}))
    {
        if(ref($SymbolInfo{$ID}{$Attr}) eq "HASH") {
            $SymbolInfo{$nID}{$Attr} = dclone($SymbolInfo{$ID}{$Attr});
        }
        else {
            $SymbolInfo{$nID}{$Attr} = $SymbolInfo{$ID}{$Attr};
        }
    }
    $SymbolInfo{$nID}{"MnglName"} = $Symbol;
}

sub selectSymbol($)
{
    my $ID = $_[0];
    
    my $MnglName = $SymbolInfo{$ID}{"MnglName"};
    
    if(not $MnglName) {
        $MnglName = $SymbolInfo{$ID}{"ShortName"};
    }
    
    if($SymbolsListPath
    and not $SymbolsList{$MnglName})
    {
        next;
    }
    
    my $Exp = 0;
    
    if($Library_Symbol{$TargetName}{$MnglName}
    or $Library_Symbol{$TargetName}{$SymVer{$MnglName}})
    {
        $Exp = 1;
    }
    
    if(my $Alias = $SymbolInfo{$ID}{"Alias"})
    {
        if($Library_Symbol{$TargetName}{$Alias}
        or $Library_Symbol{$TargetName}{$SymVer{$Alias}})
        {
            $Exp = 1;
        }
    }
    
    if(not $Exp)
    {
        if(defined $Library_UndefSymbol{$TargetName}{$MnglName}
        or defined $Library_UndefSymbol{$TargetName}{$SymVer{$MnglName}})
        {
            return 0;
        }
        
        if($SymbolInfo{$ID}{"Data"}
        or $SymbolInfo{$ID}{"InLine"}
        or $SymbolInfo{$ID}{"PureVirt"})
        {
            if(not $SymbolInfo{$ID}{"External"})
            { # skip static
                return 0;
            }
            
            if(defined $BinOnly)
            { # data, inline, pure
                return 0;
            }
            elsif(not defined $SymbolInfo{$ID}{"Header"})
            { # defined in source files
                return 0;
            }
            else
            {
                return 2;
            }
        }
        else
        {
            return 0;
        }
    }
    
    return 1;
}

sub formatName($$)
{ # type name correction
    if(defined $Cache{"formatName"}{$_[1]}{$_[0]}) {
        return $Cache{"formatName"}{$_[1]}{$_[0]};
    }
    
    my $N = $_[0];
    
    if($_[1] ne "S")
    {
        $N=~s/\A[ ]+//g;
        $N=~s/[ ]+\Z//g;
        $N=~s/[ ]{2,}/ /g;
    }
    
    $N=~s/[ ]*(\W)[ ]*/$1/g; # std::basic_string<char> const
    
    $N=~s/\b(const|volatile) ([\w\:]+)([\*&,>]|\Z)/$2 $1$3/g; # "const void" to "void const"
    
    $N=~s/\bvolatile const\b/const volatile/g;
    
    $N=~s/\b(long long|short|long) unsigned\b/unsigned $1/g;
    $N=~s/\b(short|long) int\b/$1/g;
    
    $N=~s/([\)\]])(const|volatile)\b/$1 $2/g;
    
    while($N=~s/>>/> >/g) {};
    
    if($_[1] eq "S")
    {
        if(index($N, "operator")!=-1) {
            $N=~s/\b(operator[ ]*)> >/$1>>/;
        }
    }
    
    $N=~s/,/, /g;
    
    return ($Cache{"formatName"}{$_[1]}{$_[0]} = $N);
}

sub separate_Params($)
{
    my $Str = $_[0];
    my @Parts = ();
    my %B = ( "("=>0, "<"=>0, ")"=>0, ">"=>0 );
    my $Part = 0;
    foreach my $Pos (0 .. length($Str) - 1)
    {
        my $S = substr($Str, $Pos, 1);
        if(defined $B{$S}) {
            $B{$S} += 1;
        }
        if($S eq "," and
        $B{"("}==$B{")"} and $B{"<"}==$B{">"}) {
            $Part += 1;
        }
        else {
            $Parts[$Part] .= $S;
        }
    }
    # remove spaces
    foreach (@Parts)
    {
        s/\A //g;
        s/ \Z//g;
    }
    return @Parts;
}

sub init_FuncType($$$)
{
    my ($TInfo, $FTid, $Type) = @_;
    
    $TInfo->{"Type"} = $Type;
    
    if($TInfo->{"Return"} = $DWARF_Info{$FTid}{"type"}) {
        getTypeInfo($TInfo->{"Return"});
    }
    else
    { # void
        $TInfo->{"Return"} = "1";
    }
    delete($TInfo->{"BaseType"});
    
    my @Prms = ();
    my $PPos = 0;
    foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$FuncParam{$FTid}}))
    {
        my $ParamId = $FuncParam{$FTid}{$Pos};
        my %PInfo = %{$DWARF_Info{$ParamId}};
        
        if(defined $PInfo{"artificial"})
        { # this
            next;
        }
        
        if(my $PTypeId = $PInfo{"type"})
        {
            $TInfo->{"Param"}{$PPos}{"type"} = $PTypeId;
            getTypeInfo($PTypeId);
            push(@Prms, $TypeInfo{$PTypeId}{"Name"});
        }
        
        $PPos += 1;
    }
    
    $TInfo->{"Name"} = $TypeInfo{$TInfo->{"Return"}}{"Name"};
    if($Type eq "FuncPtr") {
        $TInfo->{"Name"} .= "(*)";
    }
    else {
        $TInfo->{"Name"} .= "()";
    }
    $TInfo->{"Name"} .= "(".join(",", @Prms).")";
}

sub getShortName($)
{
    my $Name = $_[0];
    
    if(my $C = find_center($Name, "<"))
    {
        return substr($Name, 0, $C);
    }
    
    return $Name;
}

sub get_TParams($)
{
    my $ID = $_[0];
    
    my @TParams = ();
    
    foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$TmplParam{$ID}}))
    {
        my $TTid = $TmplParam{$ID}{$Pos}{"type"};
        my $Val = undef;
        my $Key = undef;
        
        if(defined $TmplParam{$ID}{$Pos}{"value"}) {
            $Val = $TmplParam{$ID}{$Pos}{"value"};
        }
        
        if(defined $TmplParam{$ID}{$Pos}{"key"}) {
            $Key = $TmplParam{$ID}{$Pos}{"key"};
        }
        
        if($Pos>0)
        {
            if(defined $TmplParam{$ID}{$Pos}{"default"})
            {
                if($Key=~/\A(_Alloc|_Traits|_Compare)\Z/)
                {
                    next;
                }
            }
        }
        
        getTypeInfo($TTid);
        
        my $TTName = $TypeInfo{$TTid}{"Name"};
        
        if(defined $Val)
        {
            if($TTName eq "bool")
            {
                if($Val eq "1") {
                    push(@TParams, "true");
                }
                elsif($Val eq "0") {
                    push(@TParams, "false");
                }
            }
            else
            {
                if($Val=~/\A\d+\Z/)
                {
                    if(my $S = $ConstSuffix{$TTName})
                    {
                        $Val .= $S;
                    }
                }
                push(@TParams, $Val);
            }
        }
        else
        {
            push(@TParams, simpleName($TTName));
        }
    }
    
    return @TParams;
}

sub parse_TParams($)
{
    my $Name = $_[0];
    if(my $Cent = find_center($Name, "<"))
    {
        my $TParams = substr($Name, $Cent);
        $TParams=~s/\A<|>\Z//g;
        
        $TParams = simpleName($TParams);
        
        my $Short = substr($Name, 0, $Cent);
        
        my @Params = separate_Params($TParams);
        foreach my $Pos (0 .. $#Params)
        {
            my $Param = $Params[$Pos];
            if($Param=~/\A(.+>)(.*?)\Z/)
            {
                my ($Tm, $Suf) = ($1, $2);
                my ($Sh, @Prm) = parse_TParams($Tm);
                $Param = $Sh."<".join(", ", @Prm).">".$Suf;
            }
            $Params[$Pos] = formatName($Param, "T");
        }
        
        @Params = shortTParams($Short, @Params);
        
        return ($Short, @Params);
    }
    
    return $Name; # error
}

sub shortTParams(@)
{
    my $Short = shift(@_);
    my @Params = @_;
    
    # default arguments
    if($Short eq "std::vector")
    {
        if($#Params==1)
        {
            if($Params[1] eq "std::allocator<".$Params[0].">")
            { # std::vector<T, std::allocator<T> >
                splice(@Params, 1, 1);
            }
        }
    }
    elsif($Short eq "std::set")
    {
        if($#Params==2)
        {
            if($Params[1] eq "std::less<".$Params[0].">"
            and $Params[2] eq "std::allocator<".$Params[0].">")
            { # std::set<T, std::less<T>, std::allocator<T> >
                splice(@Params, 1, 2);
            }
        }
    }
    elsif($Short eq "std::basic_string")
    {
        if($#Params==2)
        {
            if($Params[1] eq "std::char_traits<".$Params[0].">"
            and $Params[2] eq "std::allocator<".$Params[0].">")
            { # std::basic_string<T, std::char_traits<T>, std::allocator<T> >
                splice(@Params, 1, 2);
            }
        }
    }
    
    return @Params;
}

sub getTypeInfo($)
{
    my $ID = $_[0];
    my $Kind = $DWARF_Info{$ID}{"Kind"};
    
    if(defined $Cache{"getTypeInfo"}{$ID}) {
        return;
    }
    
    if(my $N = $NameSpace{$ID})
    {
        if($DWARF_Info{$N}{"Kind"} eq "subprogram")
        { # local code
          # template instances are declared in the subprogram (constructor)
            my $Tmpl = 0;
            if(my $ObjP = $DWARF_Info{$N}{"object_pointer"})
            {
                while($DWARF_Info{$ObjP}{"type"}) {
                    $ObjP = $DWARF_Info{$ObjP}{"type"};
                }
                my $CName = $DWARF_Info{$ObjP}{"name"};
                $CName=~s/<.*//g;
                if($CName eq $DWARF_Info{$N}{"name"}) {
                    $Tmpl = 1;
                }
            }
            if(not $Tmpl)
            { # local types
                $LocalType{$ID} = 1;
            }
        }
        elsif($DWARF_Info{$N}{"Kind"} eq "lexical_block")
        { # local code
            return;
        }
    }
    
    $Cache{"getTypeInfo"}{$ID} = 1;
    
    my %TInfo = ();
    
    $TInfo{"Type"} = $TypeType{$Kind};
    
    if(not $TInfo{"Type"})
    {
        if($DWARF_Info{$ID}{"Kind"} eq "subroutine_type") {
            $TInfo{"Type"} = "Func";
        }
    }
    
    my $RealType = $TInfo{"Type"};
    
    if(defined $ClassMethods{$ID})
    {
        if($TInfo{"Type"} eq "Struct") {
            $RealType = "Class";
        }
    }
    
    if(my $BaseType = $DWARF_Info{$ID}{"type"})
    {
        $TInfo{"BaseType"} = "$BaseType";
        
        if(defined $TypeType{$DWARF_Info{$BaseType}{"Kind"}})
        {
            getTypeInfo($TInfo{"BaseType"});
            
            if(not defined $TypeInfo{$TInfo{"BaseType"}}
            or not $TypeInfo{$TInfo{"BaseType"}}{"Name"})
            { # local code
                delete($TypeInfo{$ID});
                return;
            }
        }
    }
    if($RealType eq "Class") {
        $TInfo{"Copied"} = 1; # will be changed in getSymbolInfo()
    }
    
    if(defined $TypeMember{$ID})
    {
        my $Unnamed = 0;
        foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$TypeMember{$ID}}))
        {
            my $MemId = $TypeMember{$ID}{$Pos};
            my %MInfo = %{$DWARF_Info{$MemId}};
            
            if(my $Name = $MInfo{"name"})
            {
                if(index($Name, "_vptr.")==0)
                { # v-table pointer
                    $Name="_vptr";
                }
                $TInfo{"Memb"}{$Pos}{"name"} = $Name;
            }
            else
            {
                $TInfo{"Memb"}{$Pos}{"name"} = "unnamed".$Unnamed;
                $Unnamed += 1;
            }
            if($TInfo{"Type"} eq "Enum") {
                $TInfo{"Memb"}{$Pos}{"value"} = $MInfo{"const_value"};
            }
            else
            {
                $TInfo{"Memb"}{$Pos}{"type"} = $MInfo{"type"};
                if(my $Access = $MInfo{"accessibility"})
                {
                    if($Access ne "public")
                    { # NOTE: default access of members in the ABI dump is "public"
                        $TInfo{"Memb"}{$Pos}{"access"} = $Access;
                    }
                }
                else
                { 
                    if($DWARF_Info{$ID}{"Kind"} eq "class_type")
                    { # NOTE: default access of class members in the debug info is "private"
                        $TInfo{"Memb"}{$Pos}{"access"} = "private";
                    }
                    else
                    {
                        # NOTE: default access of struct members in the debug info is "public"
                    }
                }
                if($TInfo{"Type"} eq "Union") {
                    $TInfo{"Memb"}{$Pos}{"offset"} = "0";
                }
                elsif(defined $MInfo{"data_member_location"}) {
                    $TInfo{"Memb"}{$Pos}{"offset"} = $MInfo{"data_member_location"};
                }
            }
            
            if((my $BitSize = $MInfo{"bit_size"}) ne "") {
                $TInfo{"Memb"}{$Pos}{"bitfield"} = $BitSize;
            }
        }
    }
    
    my $NS = $NameSpace{$ID};
    if(not $NS)
    {
        if(my $Sp = $DWARF_Info{$ID}{"specification"}) {
            $NS = $NameSpace{$Sp};
        }
    }
    
    if($NS and $DWARF_Info{$NS}{"Kind"}=~/\A(class_type|structure_type)\Z/)
    { # member class
        if(my $Access = $DWARF_Info{$ID}{"accessibility"})
        {
            if($Access ne "public")
            { # NOTE: default access of member classes in the ABI dump is "public"
                $TInfo{ucfirst($Access)} = 1;
            }
        }
        else
        {
            if($DWARF_Info{$NS}{"Kind"} eq "class_type")
            {
                # NOTE: default access of member classes in the debug info is "private"
                $TInfo{"Private"} = 1;
            }
            else
            {
                # NOTE: default access to struct member classes in the debug info is "public"
            }
        }
    }
    else
    {
        if(my $Access = $DWARF_Info{$ID}{"accessibility"})
        {
            if($Access ne "public")
            { # NOTE: default access of classes in the ABI dump is "public"
                $TInfo{ucfirst($Access)} = 1;
            }
        }
    }
    
    if(my $Size = $DWARF_Info{$ID}{"byte_size"}) {
        $TInfo{"Size"} = $Size;
    }
    
    setSource(\%TInfo, $ID);
    
    if(not $DWARF_Info{$ID}{"name"}
    and my $Spec = $DWARF_Info{$ID}{"specification"}) {
        $DWARF_Info{$ID}{"name"} = $DWARF_Info{$Spec}{"name"};
    }
    
    if($NS)
    {
        if($DWARF_Info{$NS}{"Kind"} eq "namespace")
        {
            if(my $NS_F = completeNS($ID))
            {
                $TInfo{"NameSpace"} = $NS_F;
            }
        }
        elsif($DWARF_Info{$NS}{"Kind"} eq "class_type"
        or $DWARF_Info{$NS}{"Kind"} eq "structure_type")
        { # class
            getTypeInfo($NS);
            
            if(my $Sp = $SpecElem{$NS}) {
                getTypeInfo($Sp);
            }
            
            if($TypeInfo{$NS}{"Name"})
            {
                $TInfo{"NameSpace"} = $TypeInfo{$NS}{"Name"};
                $TInfo{"NameSpace"}=~s/\Astruct //;
            }
        }
    }
    
    if(my $Name = $DWARF_Info{$ID}{"name"})
    {
        $TInfo{"Name"} = $Name;
        
        if($TInfo{"NameSpace"}) {
            $TInfo{"Name"} = $TInfo{"NameSpace"}."::".$TInfo{"Name"};
        }
        
        if($TInfo{"Type"}=~/\A(Struct|Enum|Union)\Z/) {
            $TInfo{"Name"} = lc($TInfo{"Type"})." ".$TInfo{"Name"};
        }
    }
    
    if($TInfo{"Type"} eq "Pointer")
    {
        if($DWARF_Info{$TInfo{"BaseType"}}{"Kind"} eq "subroutine_type")
        {
            init_FuncType(\%TInfo, $TInfo{"BaseType"}, "FuncPtr");
        }
    }
    elsif($TInfo{"Type"}=~/Typedef|Const|Volatile/)
    {
        if($DWARF_Info{$TInfo{"BaseType"}}{"Kind"} eq "subroutine_type")
        {
            getTypeInfo($TInfo{"BaseType"});
        }
    }
    elsif($TInfo{"Type"} eq "Func")
    {
        init_FuncType(\%TInfo, $ID, "Func");
    }
    elsif($TInfo{"Type"} eq "Struct")
    {
        if(not $TInfo{"Name"}
        and my $Sb = $DWARF_Info{$ID}{"sibling"})
        {
            if($DWARF_Info{$Sb}{"Kind"} eq "subroutine_type"
            and defined $TInfo{"Memb"}
            and $TInfo{"Memb"}{0}{"name"} eq "__pfn")
            { # __pfn and __delta
                $TInfo{"Type"} = "MethodPtr";
                
                my @Prms = ();
                my $PPos = 0;
                foreach my $Pos (sort {int($a)<=>int($b)} keys(%{$FuncParam{$Sb}}))
                {
                    my $ParamId = $FuncParam{$Sb}{$Pos};
                    my %PInfo = %{$DWARF_Info{$ParamId}};
                    
                    if(defined $PInfo{"artificial"})
                    { # this
                        next;
                    }
                    
                    if(my $PTypeId = $PInfo{"type"})
                    {
                        $TInfo{"Param"}{$PPos}{"type"} = $PTypeId;
                        getTypeInfo($PTypeId);
                        push(@Prms, $TypeInfo{$PTypeId}{"Name"});
                    }
                    
                    $PPos += 1;
                }
                
                if(my $ClassId = $DWARF_Info{$Sb}{"object_pointer"})
                {
                    while($DWARF_Info{$ClassId}{"type"}) {
                        $ClassId = $DWARF_Info{$ClassId}{"type"};
                    }
                    $TInfo{"Class"} = $ClassId;
                    getTypeInfo($TInfo{"Class"});
                }
                
                if($TInfo{"Return"} = $DWARF_Info{$Sb}{"type"}) {
                    getTypeInfo($TInfo{"Return"});
                }
                else
                { # void
                    $TInfo{"Return"} = "1";
                }
                
                $TInfo{"Name"} = $TypeInfo{$TInfo{"Return"}}{"Name"};
                $TInfo{"Name"} .= "(".$TypeInfo{$TInfo{"Class"}}{"Name"}."::*)";
                $TInfo{"Name"} .= "(".join(",", @Prms).")";
            }
        }
    }
    elsif($TInfo{"Type"} eq "FieldPtr")
    {
        $TInfo{"Return"} = $TInfo{"BaseType"};
        delete($TInfo{"BaseType"});
        
        if(my $Class = $DWARF_Info{$ID}{"containing_type"})
        {
            $TInfo{"Class"} = $Class;
            getTypeInfo($TInfo{"Class"});
            
            $TInfo{"Name"} = $TypeInfo{$TInfo{"Return"}}{"Name"}."(".$TypeInfo{$TInfo{"Class"}}{"Name"}."::*)";
        }
        
        $TInfo{"Size"} = $SYS_WORD;
    }
    elsif($TInfo{"Type"} eq "String")
    {
        $TInfo{"Type"} = "Pointer";
        $TInfo{"Name"} = "char*";
        $TInfo{"BaseType"} = $TName_Tid{"Intrinsic"}{"char"};
    }
    
    foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$Inheritance{$ID}}))
    {
        if(my $BaseId = $Inheritance{$ID}{$Pos}{"id"})
        {
            if(my $E = $SpecElem{$BaseId}) {
                $BaseId = $E;
            }
            
            $TInfo{"Base"}{$BaseId}{"pos"} = "$Pos";
            if(my $Access = $Inheritance{$ID}{$Pos}{"access"}) {
                $TInfo{"Base"}{$BaseId}{"access"} = $Access;
            }
            if($Inheritance{$ID}{$Pos}{"virtual"}) {
                $TInfo{"Base"}{$BaseId}{"virtual"} = 1;
            }
            
            $ClassChild{$BaseId}{$ID} = 1;
        }
    }
    
    if($TInfo{"Type"} eq "Pointer")
    {
        if(not $TInfo{"BaseType"})
        {
            $TInfo{"Name"} = "void*";
            $TInfo{"BaseType"} = "1";
        }
    }
    if($TInfo{"Type"} eq "Const")
    {
        if(not $TInfo{"BaseType"})
        {
            $TInfo{"Name"} = "const void";
            $TInfo{"BaseType"} = "1";
        }
    }
    if($TInfo{"Type"} eq "Volatile")
    {
        if(not $TInfo{"BaseType"})
        {
            $TInfo{"Name"} = "volatile void";
            $TInfo{"BaseType"} = "1";
        }
    }
    
    if(not $TInfo{"Name"})
    {
        my $ID_ = $ID;
        my $BaseID = undef;
        my $Name = "";
        
        while($BaseID = $DWARF_Info{$ID_}{"type"})
        {
            my $Kind = $DWARF_Info{$ID_}{"Kind"};
            if(my $Q = $Qual{$TypeType{$Kind}})
            {
                $Name = $Q.$Name;
                if($Q=~/\A\w/) {
                    $Name = " ".$Name;
                }
            }
            if(my $BName = $TypeInfo{$BaseID}{"Name"})
            {
                $Name = $BName.$Name;
                last;
            }
            elsif(my $BName2 = $DWARF_Info{$BaseID}{"name"})
            {
                $Name = $BName2.$Name;
            }
            $ID_ = $BaseID;
        }
        
        if($Name) {
            $TInfo{"Name"} = $Name;
        }
        
        if($TInfo{"Type"} eq "Array")
        {
            if(my $Count = $ArrayCount{$ID})
            {
                $TInfo{"Name"} .= "[".$Count."]";
                if(my $BType = $TInfo{"BaseType"})
                {
                    if(my $BSize = $TypeInfo{$BType}{"Size"})
                    {
                        if(my $Size = $Count*$BSize)
                        {
                            $TInfo{"Size"} = "$Size";
                        }
                    }
                }
            }
            else
            {
                $TInfo{"Name"} .= "[]";
                $TInfo{"Size"} = $SYS_WORD;
            }
        }
        elsif($TInfo{"Type"} eq "Pointer")
        {
            if(my $BType = $TInfo{"BaseType"})
            {
                if($TypeInfo{$BType}{"Type"}=~/MethodPtr|FuncPtr/)
                { # void(GTestSuite::**)()
                  # int(**)(...)
                    if($TInfo{"Name"}=~s/\*\Z//) {
                        $TInfo{"Name"}=~s/\*(\))/\*\*$1/;
                    }
                }
            }
        }
    }
    
    if(my $Bid = $TInfo{"BaseType"})
    {
        if(not $TInfo{"Size"}
        and $TypeInfo{$Bid}{"Size"}) {
            $TInfo{"Size"} = $TypeInfo{$Bid}{"Size"};
        }
    }
    if($TInfo{"Name"}) {
        $TInfo{"Name"} = formatName($TInfo{"Name"}, "T"); # simpleName()
    }
    
    if($TInfo{"Name"}=~/>\Z/)
    {
        my ($Short, @TParams) = ();
        
        if(defined $TmplParam{$ID})
        {
            $Short = getShortName($TInfo{"Name"});
            @TParams = get_TParams($ID);
            @TParams = shortTParams($Short, @TParams);
        }
        else {
            ($Short, @TParams) = parse_TParams($TInfo{"Name"});
        }
        
        if(@TParams)
        {
            delete($TInfo{"TParam"});
            
            foreach my $Pos (0 .. $#TParams) {
                $TInfo{"TParam"}{$Pos}{"name"} = $TParams[$Pos];
            }
            
            $TInfo{"Name"} = formatName($Short."<".join(", ", @TParams).">", "T");
        }
    }
    
    if(not $TInfo{"Name"})
    {
        if($TInfo{"Type"}=~/\A(Class|Struct|Enum|Union)\Z/)
        {
            if($TInfo{"Header"}) {
                $TInfo{"Name"} = "anon-".lc($TInfo{"Type"})."-".$TInfo{"Header"}."-".$TInfo{"Line"};
            }
            elsif($TInfo{"Source"}) {
                $TInfo{"Name"} = "anon-".lc($TInfo{"Type"})."-".$TInfo{"Source"}."-".$TInfo{"SourceLine"};
            }
            else
            {
                if(not defined $TypeMember{$ID})
                {
                    if(not defined $ANON_TYPE_WARN{$TInfo{"Type"}})
                    {
                        printMsg("WARNING", "a \"".$TInfo{"Type"}."\" type with no attributes detected in the DWARF dump ($ID)");
                        $ANON_TYPE_WARN{$TInfo{"Type"}} = 1;
                    }
                    $TInfo{"Name"} = "anon-".lc($TInfo{"Type"});
                }
            }
            
            if($TInfo{"Name"} and $TInfo{"NameSpace"}) {
                $TInfo{"Name"} = $TInfo{"NameSpace"}."::".$TInfo{"Name"};
            }
        }
    }
    
    if($TInfo{"Name"})
    {
        if(not defined $TName_Tid{$TInfo{"Type"}}{$TInfo{"Name"}}
        or ($ID>0 and $ID<$TName_Tid{$TInfo{"Type"}}{$TInfo{"Name"}})
        or ($ID>0 and $TName_Tid{$TInfo{"Type"}}{$TInfo{"Name"}}<0))
        {
            $TName_Tid{$TInfo{"Type"}}{$TInfo{"Name"}} = "$ID";
        }
        $TName_Tids{$TInfo{"Type"}}{$TInfo{"Name"}}{$ID} = 1;
    }
    
    if(defined $TInfo{"Source"})
    {
        if(not defined $TInfo{"Header"})
        {
            $TInfo{"Line"} = $TInfo{"SourceLine"};
            delete($TInfo{"SourceLine"});
        }
    }
    
    foreach my $Attr (keys(%TInfo)) {
        $TypeInfo{$ID}{$Attr} = $TInfo{$Attr};
    }
    
    if(my $BASE_ID = $DWARF_Info{$ID}{"specification"})
    {
        foreach my $Attr (keys(%{$TypeInfo{$BASE_ID}}))
        {
            if($Attr ne "Type") {
                $TypeInfo{$ID}{$Attr} = $TypeInfo{$BASE_ID}{$Attr};
            }
        }
        
        foreach my $Attr (keys(%{$TypeInfo{$ID}})) {
            $TypeInfo{$BASE_ID}{$Attr} = $TypeInfo{$ID}{$Attr};
        }
        
        $TypeSpec{$ID} = $BASE_ID;
    }
}

sub setSource($$)
{
    my ($R, $ID) = @_;
    
    my $File = $DWARF_Info{$ID}{"decl_file"};
    my $Line = $DWARF_Info{$ID}{"decl_line"};
    
    my $Unit = $DWARF_Info{$ID}{"Unit"};
    
    if(defined $File)
    {
        my $Name = undef;
        
        if($ID>=0) {
            $Name = $SourceFile{$Unit}{$File};
        }
        else
        { # imported
            $Name = $SourceFile_Alt{0}{$File};
        }
        
        if($Name=~/\.($HEADER_EXT)\Z/)
        { # header
            $R->{"Header"} = $Name;
            if(defined $Line) {
                $R->{"Line"} = $Line;
            }
        }
        elsif(index($Name, "<built-in>")==-1)
        { # source
            $R->{"Source"} = $Name;
            if(defined $Line) {
                $R->{"SourceLine"} = $Line;
            }
        }
    }
}

sub skipSymbol($)
{
    if($SkipCxx and not $STDCXX_TARGET)
    {
        if($_[0]=~/\A(_ZS|_ZNS|_ZNKS|_ZN9__gnu_cxx|_ZNK9__gnu_cxx|_ZTIS|_ZTSS|_Zd|_Zn)/)
        { # stdc++ symbols
            return 1;
        }
    }
    return 0;
}

sub find_center($$)
{
    my ($Name, $Target) = @_;
    my %B = ( "("=>0, "<"=>0, ")"=>0, ">"=>0 );
    foreach my $Pos (0 .. length($Name)-1)
    {
        my $S = substr($Name, length($Name)-1-$Pos, 1);
        if(defined $B{$S}) {
            $B{$S}+=1;
        }
        if($S eq $Target)
        {
            if($B{"("}==$B{")"}
            and $B{"<"}==$B{">"}) {
                return length($Name)-1-$Pos;
            }
        }
    }
    return 0;
}

sub isExternal($)
{
    my $ID = $_[0];
    
    if($DWARF_Info{$ID}{"external"}) {
        return 1;
    }
    elsif(my $Spec = $DWARF_Info{$ID}{"specification"})
    {
        if($DWARF_Info{$Spec}{"external"}) {
            return 1;
        }
    }
    
    return 0;
}

sub symByAddr($)
{
    my $Loc = $_[0];
    
    my ($Addr, $Sect) = ("", "");
    if($Loc=~/\+(.+)/)
    {
        $Addr = $1;
        if(not $Addr=~s/\A0x//)
        {
            $Addr=~s/\A00//;
        }
    }
    if($Loc=~/([\w\.]+)\+/) {
        $Sect = $1;
    }
    
    if($Addr ne "")
    {
        foreach ($Sect, "")
        {
            if(defined $SymbolTable{$_}{$Addr})
            {
                if(my @Symbols = sort keys(%{$SymbolTable{$_}{$Addr}})) {
                    return $Symbols[0];
                }
            }
        }
    }
    
    return undef;
}

sub get_Mangled($)
{
    my $ID = $_[0];
    
    if(not defined $AddrToName)
    {
        if(my $Link = $DWARF_Info{$ID}{"linkage_name"})
        {
            return $Link;
        }
    }
    
    if(my $Low_Pc = $DWARF_Info{$ID}{"low_pc"})
    {
        if($Low_Pc=~/<([\w\@\.]+)>/) {
            return $1;
        }
        else
        {
            if(my $Symbol = symByAddr($Low_Pc)) {
                return $Symbol;
            }
        }
    }
    
    if(my $Loc = $DWARF_Info{$ID}{"location"})
    {
        if($Loc=~/<([\w\@\.]+)>/) {
            return $1;
        }
        else
        {
            if(my $Symbol = symByAddr($Loc)) {
                return $Symbol;
            }
        }
    }
    
    if(my $Link = $DWARF_Info{$ID}{"linkage_name"})
    {
        return $Link;
    }
    
    return undef;
}

sub completeNS($)
{
    my $ID = $_[0];
    
    my $NS = undef;
    my $ID_ = $ID;
    my @NSs = ();
    
    while($NS = $NameSpace{$ID_}
    or $NS = $NameSpace{$DWARF_Info{$ID_}{"specification"}})
    {
        if(my $N = $DWARF_Info{$NS}{"name"}) {
            push(@NSs, $N);
        }
        $ID_ = $NS;
    }
    
    if(@NSs)
    {
        my $N = join("::", reverse(@NSs));
        $NestedNameSpaces{$N} = 1;
        return $N;
    }
    
    return undef;
}

sub getSymbolInfo($)
{
    my $ID = $_[0];
    
    if(my $N = $NameSpace{$ID})
    {
        if($DWARF_Info{$N}{"Kind"} eq "lexical_block"
        or $DWARF_Info{$N}{"Kind"} eq "subprogram")
        { # local variables
            return;
        }
    }
    
    if(my $Loc = $DWARF_Info{$ID}{"location"})
    {
        if($Loc=~/ reg\d+\Z/)
        { # local variables
            return;
        }
    }
    
    my $ShortName = $DWARF_Info{$ID}{"name"};
    my $MnglName = get_Mangled($ID);
    
    if(not $MnglName)
    {
        if(my $Sp = $SpecElem{$ID})
        {
            $MnglName = get_Mangled($Sp);
            
            if(not $MnglName)
            {
                if(my $Orig = $OrigElem{$Sp})
                {
                    $MnglName = get_Mangled($Orig);
                }
            }
        }
    }
    
    if(not $MnglName)
    {
        if(index($ShortName, "<")!=-1)
        { # template
            return;
        }
        $MnglName = $ShortName;
    }
    
    if(skipSymbol($MnglName)) {
        return;
    }
    
    if(index($MnglName, "\@")!=-1) {
        $MnglName=~s/([\@]+.*?)\Z//;
    }
    
    if(not $MnglName) {
        return;
    }
    
    if(index($MnglName, ".")!=-1)
    { # foo.part.14
      # bar.isra.15
        return;
    }
    
    if($MnglName=~/\W/)
    { # unmangled operators, etc.
        return;
    }
    
    if($MnglName)
    {
        if(my $OLD_ID = $Mangled_ID{$MnglName})
        { # duplicates
            if(not defined $SymbolInfo{$OLD_ID}{"Header"}
            or not defined $SymbolInfo{$OLD_ID}{"Source"})
            {
                setSource($SymbolInfo{$OLD_ID}, $ID);
            }
            
            if(not defined $SymbolInfo{$OLD_ID}{"ShortName"}
            and $ShortName) {
                $SymbolInfo{$OLD_ID}{"ShortName"} = $ShortName;
            }
            
            if(defined $DWARF_Info{$OLD_ID}{"low_pc"}
            or not defined $DWARF_Info{$ID}{"low_pc"})
            {
                if(defined $Checked_Spec{$MnglName}
                or not $DWARF_Info{$ID}{"specification"})
                {
                    if(not defined $SpecElem{$ID}
                    and not defined $OrigElem{$ID}) {
                        delete($DWARF_Info{$ID});
                    }
                    return;
                }
            }
        }
    }
    
    my %SInfo = ();
    
    if($ShortName) {
        $SInfo{"ShortName"} = $ShortName;
    }
    $SInfo{"MnglName"} = $MnglName;
    
    if($ShortName)
    {
        if($MnglName eq $ShortName)
        {
            delete($SInfo{"MnglName"});
            $MnglName = $ShortName;
        }
        elsif(index($MnglName, "_Z")!=0)
        {
            if($SInfo{"ShortName"})
            {
                $SInfo{"Alias"} = $SInfo{"ShortName"};
                $SInfo{"ShortName"} = $SInfo{"MnglName"};
            }
            
            delete($SInfo{"MnglName"});
            $MnglName = $ShortName;
            # $ShortName = $SInfo{"ShortName"};
        }
    }
    else
    {
        if(index($MnglName, "_Z")!=0)
        {
            $SInfo{"ShortName"} = $SInfo{"MnglName"};
            delete($SInfo{"MnglName"});
        }
    }
    
    if(isExternal($ID)) {
        $SInfo{"External"} = 1;
    }
    
    if(my $Orig = $DWARF_Info{$ID}{"abstract_origin"})
    {
        if(isExternal($Orig)) {
            $SInfo{"External"} = 1;
        }
    }
    
    if(index($MnglName, "_ZNVK")==0)
    {
        $SInfo{"Const"} = 1;
        $SInfo{"Volatile"} = 1;
    }
    elsif(index($MnglName, "_ZNV")==0) {
        $SInfo{"Volatile"} = 1;
    }
    elsif(index($MnglName, "_ZNK")==0) {
        $SInfo{"Const"} = 1;
    }
    
    if($DWARF_Info{$ID}{"artificial"}) {
        $SInfo{"Artificial"} = 1;
    }
    
    my ($C, $D) = ();
    
    if($MnglName=~/C[1-4][EI].+/)
    {
        $C = 1;
        $SInfo{"Constructor"} = 1;
    }
    
    if($MnglName=~/D[0-4][EI].+/)
    {
        $D = 1;
        $SInfo{"Destructor"} = 1;
    }
    
    if($C or $D)
    {
        if(my $Orig = $DWARF_Info{$ID}{"abstract_origin"})
        {
            if(my $InLine = $DWARF_Info{$Orig}{"inline"})
            {
                if(index($InLine, "declared_not_inlined")==0)
                {
                    $SInfo{"InLine"} = 1;
                    $SInfo{"Artificial"} = 1;
                }
            }
            
            setSource(\%SInfo, $Orig);
            
            if(my $Spec = $DWARF_Info{$Orig}{"specification"})
            {
                setSource(\%SInfo, $Spec);
                
                $SInfo{"ShortName"} = $DWARF_Info{$Spec}{"name"};
                if($D) {
                    $SInfo{"ShortName"}=~s/\A\~//g;
                }
                
                if(my $Class = $NameSpace{$Spec}) {
                    $SInfo{"Class"} = $Class;
                }
                
                if(my $Virt = $DWARF_Info{$Spec}{"virtuality"})
                {
                    if(index($Virt, "virtual")!=-1) {
                        $SInfo{"Virt"} = 1;
                    }
                }
                
                if(my $Access = $DWARF_Info{$Spec}{"accessibility"})
                {
                    if($Access ne "public")
                    { # default access of methods in the ABI dump is "public"
                        $SInfo{ucfirst($Access)} = 1;
                    }
                }
                else
                { # NOTE: default access of class methods in the debug info is "private"
                    if($TypeInfo{$SInfo{"Class"}}{"Type"} eq "Class")
                    {
                        $SInfo{"Private"} = 1;
                    }
                }
                
                # clean origin
                delete($SymbolInfo{$Spec});
            }
        }
    }
    else
    {
        if(my $InLine = $DWARF_Info{$ID}{"inline"})
        {
            if(index($InLine, "declared_inlined")==0) {
                $SInfo{"InLine"} = 1;
            }
        }
    }
    
    if(defined $AddrToName)
    {
        if(not $SInfo{"Alias"}
        and not $SInfo{"Constructor"}
        and not $SInfo{"Destructor"})
        {
            if(my $Linkage = $DWARF_Info{$ID}{"linkage_name"})
            {
                if($Linkage ne $MnglName) {
                    $SInfo{"Alias"} = $Linkage;
                }
            }
        }
    }
    
    if($DWARF_Info{$ID}{"Kind"} eq "variable")
    { # global data
        $SInfo{"Data"} = 1;
        
        if(my $Spec = $DWARF_Info{$ID}{"specification"})
        {
            if($DWARF_Info{$Spec}{"Kind"} eq "member")
            {
                setSource(\%SInfo, $Spec);
                $SInfo{"ShortName"} = $DWARF_Info{$Spec}{"name"};
                
                if(my $NSp = $NameSpace{$Spec})
                {
                    if($DWARF_Info{$NSp}{"Kind"} eq "namespace") {
                        $SInfo{"NameSpace"} = completeNS($Spec);
                    }
                    else {
                        $SInfo{"Class"} = $NSp;
                    }
                }
            }
        }
    }
    
    if(my $Access = $DWARF_Info{$ID}{"accessibility"})
    {
        if($Access ne "public")
        { # default access of methods in the ABI dump is "public"
            $SInfo{ucfirst($Access)} = 1;
        }
    }
    elsif(not $DWARF_Info{$ID}{"specification"}
    and not $DWARF_Info{$ID}{"abstract_origin"})
    {
        if(my $NS = $NameSpace{$ID})
        {
            if(defined $TypeInfo{$NS})
            { # NOTE: default access of class methods in the debug info is "private"
                if($TypeInfo{$NS}{"Type"} eq "Class")
                {
                    $SInfo{"Private"} = 1;
                }
            }
        }
    }
    
    if(my $Class = $DWARF_Info{$ID}{"containing_type"})
    {
        $SInfo{"Class"} = $Class;
    }
    
    if(my $NS = $NameSpace{$ID})
    {
        if($DWARF_Info{$NS}{"Kind"} eq "namespace") {
            $SInfo{"NameSpace"} = completeNS($ID);
        }
        else {
            $SInfo{"Class"} = $NS;
        }
    }
    
    if($SInfo{"Class"} and $MnglName
    and index($MnglName, "_Z")!=0)
    {
        return;
    }
    
    if(my $Return = $DWARF_Info{$ID}{"type"})
    {
        $SInfo{"Return"} = $Return;
    }
    if(my $Spec = $DWARF_Info{$ID}{"specification"})
    {
        if(not $DWARF_Info{$ID}{"type"}) {
            $SInfo{"Return"} = $DWARF_Info{$Spec}{"type"};
        }
        if(my $Value = $DWARF_Info{$Spec}{"const_value"})
        {
            if($Value=~/ block:\s*(.*?)\Z/) {
                $Value = $1;
            }
            $SInfo{"Value"} = $Value;
        }
    }
    
    if($SInfo{"ShortName"}=~/>\Z/)
    { # foo<T1, T2, ...>
        my ($Short, @TParams) = ();
        
        if(defined $TmplParam{$ID})
        {
            $Short = getShortName($SInfo{"ShortName"});
            @TParams = get_TParams($ID);
            @TParams = shortTParams($Short, @TParams);
        }
        else {
            ($Short, @TParams) = parse_TParams($SInfo{"ShortName"});
        }
        
        if(@TParams)
        {
            foreach my $Pos (0 .. $#TParams) {
                $SInfo{"TParam"}{$Pos}{"name"} = formatName($TParams[$Pos], "T");
            }
            # simplify short name
            $SInfo{"ShortName"} = $Short.formatName("<".join(", ", @TParams).">", "T");
        }
    }
    elsif($SInfo{"ShortName"}=~/\Aoperator (\w.*)\Z/)
    { # operator type<T1>::name
        $SInfo{"ShortName"} = "operator ".simpleName($1);
    }
    
    if(my $Virt = $DWARF_Info{$ID}{"virtuality"})
    {
        if(index($Virt, "virtual")!=-1)
        {
            if($D or defined $SpecElem{$ID}) {
                $SInfo{"Virt"} = 1;
            }
            else {
                $SInfo{"PureVirt"} = 1;
            }
        }
        
        if((my $VirtPos = $DWARF_Info{$ID}{"vtable_elem_location"}) ne "")
        {
            $SInfo{"VirtPos"} = $VirtPos;
        }
    }
    
    setSource(\%SInfo, $ID);
    
    if(not $SInfo{"Header"})
    {
        if($SInfo{"Class"})
        { # detect missed header by class
            if(defined $TypeInfo{$SInfo{"Class"}}{"Header"}) {
                $SInfo{"Header"} = $TypeInfo{$SInfo{"Class"}}{"Header"};
            }
        }
    }
    
    if(not $SInfo{"Header"})
    {
        if(defined $SymbolToHeader{$MnglName}) {
            $SInfo{"Header"} = $SymbolToHeader{$MnglName};
        }
        elsif(not $SInfo{"Class"}
        and defined $SymbolToHeader{$SInfo{"ShortName"}}) {
            $SInfo{"Header"} = $SymbolToHeader{$SInfo{"ShortName"}};
        }
    }
    elsif($SInfo{"Alias"})
    {
        if(defined $SymbolToHeader{$SInfo{"Alias"}}
        and $SymbolToHeader{$SInfo{"Alias"}} ne $SInfo{"Header"})
        { # TODO: review this case
            $SInfo{"Header"} = $SymbolToHeader{$SInfo{"Alias"}};
        }
    }
    
    my $PPos = 0;
    
    foreach my $Pos (sort {int($a) <=> int($b)} keys(%{$FuncParam{$ID}}))
    {
        my $ParamId = $FuncParam{$ID}{$Pos};
        my $Offset = undef;
        my $Reg = undef;
        
        if(my $Sp = $SpecElem{$ID})
        {
            if(defined $FuncParam{$Sp}) {
                $ParamId = $FuncParam{$Sp}{$Pos};
            }
        }
        
        if((my $Loc = $DWARF_Info{$ParamId}{"location"}) ne "") {
            $Offset = $Loc;
        }
        elsif((my $R = $DWARF_Info{$ParamId}{"register"}) ne "") {
            $Reg = $RegName{$R};
        }
        elsif((my $LL = $DWARF_Info{$ParamId}{"location_list"}) ne "")
        {
            if(my $L = $DebugLoc{$LL})
            {
                if($L=~/reg(\d+)/) {
                    $Reg = $RegName{$1};
                }
                elsif($L=~/fbreg\s+(-?\w+)\Z/) {
                    $Offset = $1;
                }
            }
            elsif(not defined $DebugLoc{$LL})
            { # invalid debug_loc
                if(not $InvalidDebugLoc)
                {
                    printMsg("ERROR", "invalid debug_loc section of object, please fix your elf utils");
                    $InvalidDebugLoc = 1;
                }
            }
        }
        
        if(my $Orig = $DWARF_Info{$ParamId}{"abstract_origin"}) {
            $ParamId = $Orig;
        }
        
        my %PInfo = %{$DWARF_Info{$ParamId}};
        
        if(defined $Offset) {
            $SInfo{"Param"}{$Pos}{"offset"} = $Offset;
        }
        
        if($TypeInfo{$PInfo{"type"}}{"Type"} eq "Const")
        {
            if(my $BTid = $TypeInfo{$PInfo{"type"}}{"BaseType"})
            {
                if($TypeInfo{$BTid}{"Type"} eq "Ref")
                { # const&const -> const&
                    $PInfo{"type"} = $BTid;
                }
            }
        }
        
        $SInfo{"Param"}{$Pos}{"type"} = $PInfo{"type"};
        
        if(defined $PInfo{"name"}) {
            $SInfo{"Param"}{$Pos}{"name"} = $PInfo{"name"};
        }
        elsif($TypeInfo{$PInfo{"type"}}{"Name"} ne "...") {
            $SInfo{"Param"}{$Pos}{"name"} = "p".($PPos+1);
        }
        
        if(defined $Reg)
        {
            $SInfo{"Reg"}{$Pos} = $Reg;
        }
        
        if($DWARF_Info{$ParamId}{"artificial"} and $Pos==0)
        {
            if($SInfo{"Param"}{$Pos}{"name"} eq "p1") {
                $SInfo{"Param"}{$Pos}{"name"} = "this";
            }
        }
        
        if($SInfo{"Param"}{$Pos}{"name"} ne "this")
        { # this, p1, p2, etc.
            $PPos += 1;
        }
    }
    
    if($SInfo{"Constructor"} and not $SInfo{"InLine"}
    and $SInfo{"Class"}) {
        delete($TypeInfo{$SInfo{"Class"}}{"Copied"});
    }
    
    if(my $BASE_ID = $Mangled_ID{$MnglName})
    {
        if(defined $SInfo{"Param"})
        {
            if(keys(%{$SInfo{"Param"}})!=keys(%{$SymbolInfo{$BASE_ID}{"Param"}}))
            { # different symbols with the same name
                delete($SymbolInfo{$BASE_ID});
            }
        }
        
        $ID = $BASE_ID;
        
        if(defined $SymbolInfo{$ID}{"PureVirt"})
        { # if the specification of a symbol is located in other compile unit
            delete($SymbolInfo{$ID}{"PureVirt"});
            $SymbolInfo{$ID}{"Virt"} = 1;
        }
    }
    $Mangled_ID{$MnglName} = $ID;
    
    if($DWARF_Info{$ID}{"specification"}) {
        $Checked_Spec{$MnglName} = 1;
    }
    
    foreach my $Attr (keys(%SInfo))
    {
        if(ref($SInfo{$Attr}) eq "HASH")
        {
            foreach my $K1 (keys(%{$SInfo{$Attr}}))
            {
                if(ref($SInfo{$Attr}{$K1}) eq "HASH")
                {
                    foreach my $K2 (keys(%{$SInfo{$Attr}{$K1}}))
                    {
                        $SymbolInfo{$ID}{$Attr}{$K1}{$K2} = $SInfo{$Attr}{$K1}{$K2};
                    }
                }
                else {
                    $SymbolInfo{$ID}{$Attr}{$K1} = $SInfo{$Attr}{$K1};
                }
            }
        }
        else
        {
            $SymbolInfo{$ID}{$Attr} = $SInfo{$Attr};
        }
    }
    
    if($ID>$GLOBAL_ID) {
        $GLOBAL_ID = $ID;
    }
}

sub getTypeIdByName($$)
{
    my ($Type, $Name) = @_;
    return $TName_Tid{$Type}{formatName($Name, "T")};
}

sub getFirst($)
{
    my $Tid = $_[0];
    if(not $Tid) {
        return $Tid;
    }
    
    if(defined $TypeSpec{$Tid}) {
        $Tid = $TypeSpec{$Tid};
    }
    
    my $F = 0;
    
    if(my $Name = $TypeInfo{$Tid}{"Name"})
    {
        my $Type = $TypeInfo{$Tid}{"Type"};
        if($Name=~s/\Astruct //)
        { # search for class or derived types (const, *, etc.)
            $F = 1;
        }
        
        my $FTid = undef;
        if($F)
        {
            foreach my $Type ("Class", "Const", "Ref", "RvalueRef", "Pointer")
            {
                if($FTid = $TName_Tid{$Type}{$Name})
                {
                    if($FTid ne $Tid)
                    {
                        $MergedTypes{$Tid} = 1;
                    }
                    return "$FTid";
                }
            }
            
            $Name = "struct ".$Name;
        }
        
        if(not $FTid) {
            $FTid = $TName_Tid{$Type}{$Name};
        }
        
        if($FTid) {
            return "$FTid";
        }
        printMsg("ERROR", "internal error (missed type id $Tid)");
    }
    
    return $Tid;
}

sub searchTypeID($)
{
    my $Name = $_[0];
    
    my %Pr = map {$_=>1} (
        "Struct",
        "Union",
        "Enum"
    );
    
    foreach my $Type ("Class", "Struct", "Union", "Enum", "Typedef", "Const",
    "Volatile", "Ref", "RvalueRef", "Pointer", "FuncPtr", "MethodPtr", "FieldPtr")
    {
        my $Tid = $TName_Tid{$Type}{$Name};
        
        if(not $Tid)
        {
            my $P = "";
            if(defined $Pr{$Type})
            {
                $P = lc($Type)." ";
            }
            
            $Tid = $TName_Tid{$Type}{$P.$Name}
        }
        if($Tid) {
            return $Tid;
        }
    }
    return undef;
}

sub remove_Unused()
{ # remove unused data types from the ABI dump
    %HeadersInfo = ();
    %SourcesInfo = ();
    
    my (%SelectedHeaders, %SelectedSources) = ();
    
    foreach my $ID (sort {int($a)<=>int($b)} keys(%SymbolInfo))
    {
        if($SelectedSymbols{$ID}==2)
        { # data, inline, pure
            next;
        }
        
        register_SymbolUsage($ID);
        
        if(my $H = $SymbolInfo{$ID}{"Header"}) {
            $SelectedHeaders{$H} = 1;
        }
        if(my $S = $SymbolInfo{$ID}{"Source"}) {
            $SelectedSources{$S} = 1;
        }
    }
    
    foreach my $ID (sort {int($a)<=>int($b)} keys(%SymbolInfo))
    {
        if($SelectedSymbols{$ID}==2)
        { # data, inline, pure
            my $Save = 0;
            if(my $Class = $SymbolInfo{$ID}{"Class"})
            {
                if(defined $UsedType{$Class}) {
                    $Save = 1;
                }
                else
                {
                    foreach (keys(%{$ClassChild{$Class}}))
                    {
                        if(defined $UsedType{$_})
                        {
                            $Save = 1;
                            last;
                        }
                    }
                }
            }
            if(my $Header = $SymbolInfo{$ID}{"Header"})
            {
                if(defined $SelectedHeaders{$Header}) {
                    $Save = 1;
                }
            }
            if(my $Source = $SymbolInfo{$ID}{"Source"})
            {
                if(defined $SelectedSources{$Source}) {
                    $Save = 1;
                }
            }
            if($Save) {
                register_SymbolUsage($ID);
            }
            else {
                delete($SymbolInfo{$ID});
            }
        }
    }
    
    if(defined $AllTypes)
    {
        # register all data types (except anon structs and unions)
        foreach my $Tid (keys(%TypeInfo))
        {
            if(defined $LocalType{$Tid})
            { # except local code
                next;
            }
            if($TypeInfo{$Tid}{"Type"} eq "Enum"
            or index($TypeInfo{$Tid}{"Name"}, "anon-")!=0) {
                register_TypeUsage($Tid);
            }
        }
        
        # remove unused anons (except enums)
        foreach my $Tid (keys(%TypeInfo))
        {
            if(not $UsedType{$Tid})
            {
                if($TypeInfo{$Tid}{"Type"} ne "Enum")
                {
                    if(index($TypeInfo{$Tid}{"Name"}, "anon-")==0) {
                        delete($TypeInfo{$Tid});
                    }
                }
            }
        }
        
        # remove duplicates
        foreach my $Tid (keys(%TypeInfo))
        {
            my $Name = $TypeInfo{$Tid}{"Name"};
            my $Type = $TypeInfo{$Tid}{"Type"};
            
            if($TName_Tid{$Type}{$Name} ne $Tid) {
                delete($TypeInfo{$Tid});
            }
        }
    }
    else
    {
        foreach my $Tid (keys(%TypeInfo))
        { # remove unused types
            if(not $UsedType{$Tid}) {
                delete($TypeInfo{$Tid});
            }
        }
    }
    
    foreach my $Tid (keys(%MergedTypes)) {
        delete($TypeInfo{$Tid});
    }
    
    foreach my $Tid (keys(%LocalType))
    {
        if(not $UsedType{$Tid}) {
            delete($TypeInfo{$Tid});
        }
    }
    
    # clean memory
    %MergedTypes = ();
    %LocalType = ();
    
    # completeness
    foreach my $Tid (sort keys(%TypeInfo)) {
        check_Completeness($TypeInfo{$Tid});
    }
    
    foreach my $Sid (sort keys(%SymbolInfo)) {
        check_Completeness($SymbolInfo{$Sid});
    }
    
    # clean memory
    %UsedType = ();
}

sub simpleName($)
{
    my $N = $_[0];
    
    $N=~s/\A(struct|class|union|enum) //; # struct, class, union, enum
    
    if(index($N, "std::basic_string")!=-1)
    {
        $N=~s/std::basic_string<char, std::char_traits<char>, std::allocator<char> >/std::string /g;
        $N=~s/std::basic_string<char, std::char_traits<char> >/std::string /g;
        $N=~s/std::basic_string<char>/std::string /g;
    }
    
    return formatName($N, "T");
}

sub register_SymbolUsage($)
{
    my $InfoId = $_[0];
    
    my %FuncInfo = %{$SymbolInfo{$InfoId}};
    
    if(my $S = $FuncInfo{"Source"}) {
        $SourcesInfo{$S} = 1;
    }
    if(my $H = $FuncInfo{"Header"}) {
        $HeadersInfo{$H} = 1;
    }
    if(my $RTid = getFirst($FuncInfo{"Return"}))
    {
        register_TypeUsage($RTid);
        $SymbolInfo{$InfoId}{"Return"} = $RTid;
    }
    if(my $FCid = getFirst($FuncInfo{"Class"}))
    {
        register_TypeUsage($FCid);
        $SymbolInfo{$InfoId}{"Class"} = $FCid;
        
        if(my $ThisId = getTypeIdByName("Const", $TypeInfo{$FCid}{"Name"}."*const"))
        { # register "this" pointer
            register_TypeUsage($ThisId);
        }
        if(my $ThisId_C = getTypeIdByName("Const", $TypeInfo{$FCid}{"Name"}." const*const"))
        { # register "this" pointer (const method)
            register_TypeUsage($ThisId_C);
        }
    }
    foreach my $PPos (keys(%{$FuncInfo{"Param"}}))
    {
        if(my $PTid = getFirst($FuncInfo{"Param"}{$PPos}{"type"}))
        {
            register_TypeUsage($PTid);
            $SymbolInfo{$InfoId}{"Param"}{$PPos}{"type"} = $PTid;
        }
    }
    foreach my $TPos (keys(%{$FuncInfo{"TParam"}}))
    {
        my $TPName = $FuncInfo{"TParam"}{$TPos}{"name"};
        if(my $TTid = searchTypeID($TPName))
        {
            if(my $FTTid = getFirst($TTid)) {
                register_TypeUsage($FTTid);
            }
        }
    }
}

sub register_TypeUsage($)
{
    my $TypeId = $_[0];
    if(not $TypeId) {
        return 0;
    }
    if($UsedType{$TypeId})
    { # already registered
        return 1;
    }
    my %TInfo = %{$TypeInfo{$TypeId}};
    
    if(my $S = $TInfo{"Source"}) {
        $SourcesInfo{$S} = 1;
    }
    if(my $H = $TInfo{"Header"}) {
        $HeadersInfo{$H} = 1;
    }
    
    if($TInfo{"Type"})
    {
        if(my $NS = $TInfo{"NameSpace"})
        {
            if(my $NSTid = searchTypeID($NS))
            {
                if(my $FNSTid = getFirst($NSTid)) {
                    register_TypeUsage($FNSTid);
                }
            }
        }
        
        if($TInfo{"Type"}=~/\A(Struct|Union|Class|FuncPtr|Func|MethodPtr|FieldPtr|Enum)\Z/)
        {
            $UsedType{$TypeId} = 1;
            if($TInfo{"Type"}=~/\A(Struct|Class)\Z/)
            {
                foreach my $BaseId (keys(%{$TInfo{"Base"}}))
                { # register base classes
                    if(my $FBaseId = getFirst($BaseId))
                    {
                        register_TypeUsage($FBaseId);
                        if($FBaseId ne $BaseId)
                        {
                            %{$TypeInfo{$TypeId}{"Base"}{$FBaseId}} = %{$TypeInfo{$TypeId}{"Base"}{$BaseId}};
                            delete($TypeInfo{$TypeId}{"Base"}{$BaseId});
                        }
                    }
                }
                foreach my $TPos (keys(%{$TInfo{"TParam"}}))
                {
                    my $TPName = $TInfo{"TParam"}{$TPos}{"name"};
                    if(my $TTid = searchTypeID($TPName))
                    {
                        if(my $FTTid = getFirst($TTid)) {
                            register_TypeUsage($FTTid);
                        }
                    }
                }
            }
            foreach my $Memb_Pos (keys(%{$TInfo{"Memb"}}))
            {
                if(my $MTid = getFirst($TInfo{"Memb"}{$Memb_Pos}{"type"}))
                {
                    register_TypeUsage($MTid);
                    $TypeInfo{$TypeId}{"Memb"}{$Memb_Pos}{"type"} = $MTid;
                }
            }
            if($TInfo{"Type"} eq "FuncPtr"
            or $TInfo{"Type"} eq "MethodPtr"
            or $TInfo{"Type"} eq "Func")
            {
                if(my $RTid = getFirst($TInfo{"Return"}))
                {
                    register_TypeUsage($RTid);
                    $TypeInfo{$TypeId}{"Return"} = $RTid;
                }
                foreach my $Memb_Pos (keys(%{$TInfo{"Param"}}))
                {
                    if(my $MTid = getFirst($TInfo{"Param"}{$Memb_Pos}{"type"}))
                    {
                        register_TypeUsage($MTid);
                        $TypeInfo{$TypeId}{"Param"}{$Memb_Pos}{"type"} = $MTid;
                    }
                }
            }
            if($TInfo{"Type"} eq "FieldPtr")
            {
                if(my $RTid = getFirst($TInfo{"Return"}))
                {
                    register_TypeUsage($RTid);
                    $TypeInfo{$TypeId}{"Return"} = $RTid;
                }
                if(my $CTid = getFirst($TInfo{"Class"}))
                {
                    register_TypeUsage($CTid);
                    $TypeInfo{$TypeId}{"Class"} = $CTid;
                }
            }
            if($TInfo{"Type"} eq "MethodPtr")
            {
                if(my $CTid = getFirst($TInfo{"Class"}))
                {
                    register_TypeUsage($CTid);
                    $TypeInfo{$TypeId}{"Class"} = $CTid;
                }
            }
            if($TInfo{"Type"} eq "Enum")
            {
                if(my $BTid = getFirst($TInfo{"BaseType"}))
                {
                    register_TypeUsage($BTid);
                    $TypeInfo{$TypeId}{"BaseType"} = $BTid;
                }
            }
            return 1;
        }
        elsif($TInfo{"Type"}=~/\A(Const|ConstVolatile|Volatile|Pointer|Ref|RvalueRef|Restrict|Array|Typedef)\Z/)
        {
            $UsedType{$TypeId} = 1;
            if(my $BTid = getFirst($TInfo{"BaseType"}))
            {
                register_TypeUsage($BTid);
                $TypeInfo{$TypeId}{"BaseType"} = $BTid;
            }
            return 1;
        }
        elsif($TInfo{"Type"} eq "Intrinsic")
        {
            $UsedType{$TypeId} = 1;
            return 1;
        }
    }
    return 0;
}

my %CheckedType = ();

sub check_Completeness($)
{
    my $Info = $_[0];
    
    # data types
    if(defined $Info->{"Memb"})
    {
        foreach my $Pos (sort keys(%{$Info->{"Memb"}}))
        {
            if(defined $Info->{"Memb"}{$Pos}{"type"}) {
                check_TypeInfo($Info->{"Memb"}{$Pos}{"type"});
            }
        }
    }
    if(defined $Info->{"Base"})
    {
        foreach my $Bid (sort keys(%{$Info->{"Base"}})) {
            check_TypeInfo($Bid);
        }
    }
    if(defined $Info->{"BaseType"}) {
        check_TypeInfo($Info->{"BaseType"});
    }
    if(defined $Info->{"TParam"})
    {
        foreach my $Pos (sort keys(%{$Info->{"TParam"}}))
        {
            my $TName = $Info->{"TParam"}{$Pos}{"name"};
            if($TName=~/\A(true|false|\d.*)\Z/) {
                next;
            }
            
            if(my $Tid = searchTypeID($TName)) {
                check_TypeInfo($Tid);
            }
            else
            {
                if(defined $Loud) {
                    printMsg("WARNING", "missed type $TName");
                }
            }
        }
    }
    
    # symbols
    if(defined $Info->{"Param"})
    {
        foreach my $Pos (sort keys(%{$Info->{"Param"}}))
        {
            if(defined $Info->{"Param"}{$Pos}{"type"}) {
                check_TypeInfo($Info->{"Param"}{$Pos}{"type"});
            }
        }
    }
    if(defined $Info->{"Return"}) {
        check_TypeInfo($Info->{"Return"});
    }
    if(defined $Info->{"Class"}) {
        check_TypeInfo($Info->{"Class"});
    }
}

sub check_TypeInfo($)
{
    my $Tid = $_[0];
    
    if(defined $CheckedType{$Tid}) {
        return;
    }
    $CheckedType{$Tid} = 1;
    
    if(defined $TypeInfo{$Tid})
    {
        if(not $TypeInfo{$Tid}{"Name"}) {
            printMsg("ERROR", "missed type name ($Tid)");
        }
        check_Completeness($TypeInfo{$Tid});
    }
    else {
        printMsg("ERROR", "missed type id $Tid");
    }
}

sub init_Registers()
{
    if($SYS_ARCH eq "x86")
    {
        %RegName = (
        # integer registers
        # 32 bits
            "0"=>"eax",
            "1"=>"ecx",
            "2"=>"edx",
            "3"=>"ebx",
            "4"=>"esp",
            "5"=>"ebp",
            "6"=>"esi",
            "7"=>"edi",
            "8"=>"eip",
            "9"=>"eflags",
            "10"=>"trapno",
        # FPU-control registers
        # 16 bits
            "37"=>"fctrl",
            "38"=>"fstat",
        # 32 bits
            "39"=>"mxcsr",
        # MMX registers
        # 64 bits
            "29"=>"mm0",
            "30"=>"mm1",
            "31"=>"mm2",
            "32"=>"mm3",
            "33"=>"mm4",
            "34"=>"mm5",
            "35"=>"mm6",
            "36"=>"mm7",
        # SSE registers
        # 128 bits
            "21"=>"xmm0",
            "22"=>"xmm1",
            "23"=>"xmm2",
            "24"=>"xmm3",
            "25"=>"xmm4",
            "26"=>"xmm5",
            "27"=>"xmm6",
            "28"=>"xmm7",
        # segment registers
        # 16 bits
            "40"=>"es",
            "41"=>"cs",
            "42"=>"ss",
            "43"=>"ds",
            "44"=>"fs",
            "45"=>"gs",
        # x87 registers
        # 80 bits
            "11"=>"st0",
            "12"=>"st1",
            "13"=>"st2",
            "14"=>"st3",
            "15"=>"st4",
            "16"=>"st5",
            "17"=>"st6",
            "18"=>"st7"
        );
    }
    elsif($SYS_ARCH eq "x86_64")
    {
        %RegName = (
        # integer registers
        # 64 bits
            "0"=>"rax",
            "1"=>"rdx",
            "2"=>"rcx",
            "3"=>"rbx",
            "4"=>"rsi",
            "5"=>"rdi",
            "6"=>"rbp",
            "7"=>"rsp",
            "8"=>"r8",
            "9"=>"r9",
            "10"=>"r10",
            "11"=>"r11",
            "12"=>"r12",
            "13"=>"r13",
            "14"=>"r14",
            "15"=>"r15",
            "16"=>"rip",
            "49"=>"rFLAGS",
        # MMX registers
        # 64 bits
            "41"=>"mm0",
            "42"=>"mm1",
            "43"=>"mm2",
            "44"=>"mm3",
            "45"=>"mm4",
            "46"=>"mm5",
            "47"=>"mm6",
            "48"=>"mm7",
        # SSE registers
        # 128 bits
            "17"=>"xmm0",
            "18"=>"xmm1",
            "19"=>"xmm2",
            "20"=>"xmm3",
            "21"=>"xmm4",
            "22"=>"xmm5",
            "23"=>"xmm6",
            "24"=>"xmm7",
            "25"=>"xmm8",
            "26"=>"xmm9",
            "27"=>"xmm10",
            "28"=>"xmm11",
            "29"=>"xmm12",
            "30"=>"xmm13",
            "31"=>"xmm14",
            "32"=>"xmm15",
        # control registers
        # 64 bits
            "62"=>"tr", 
            "63"=>"ldtr",
            "64"=>"mxcsr",
        # 16 bits
            "65"=>"fcw",
            "66"=>"fsw",
        # segment registers
        # 16 bits
            "50"=>"es",
            "51"=>"cs",
            "52"=>"ss",
            "53"=>"ds",
            "54"=>"fs",
            "55"=>"gs",
        # 64 bits
            "58"=>"fs.base",
            "59"=>"gs.base",
        # x87 registers
        # 80 bits
            "33"=>"st0",
            "34"=>"st1",
            "35"=>"st2",
            "36"=>"st3",
            "37"=>"st4",
            "38"=>"st5",
            "39"=>"st6",
            "40"=>"st7"
        );
    }
    elsif($SYS_ARCH eq "arm")
    {
        %RegName = (
        # integer registers
        # 32-bit
            "0"=>"r0",
            "1"=>"r1",
            "2"=>"r2",
            "3"=>"r3",
            "4"=>"r4",
            "5"=>"r5",
            "6"=>"r6",
            "7"=>"r7",
            "8"=>"r8",
            "9"=>"r9",
            "10"=>"r10",
            "11"=>"r11",
            "12"=>"r12",
            "13"=>"r13",
            "14"=>"r14",
            "15"=>"r15"
        );
    }
}

sub dump_sorting($)
{
    my $Hash = $_[0];
    return [] if(not $Hash);
    my @Keys = keys(%{$Hash});
    return [] if($#Keys<0);
    if($Keys[0]=~/\A\d+\Z/)
    { # numbers
        return [sort {int($a)<=>int($b)} @Keys];
    }
    else
    { # strings
        return [sort {$a cmp $b} @Keys];
    }
}

sub getDebugFile($$)
{
    my ($Obj, $Header) = @_;
    
    my $Str = `$EU_READELF_L --strings=.$Header \"$Obj\" 2>\"$TMP_DIR/error\"`;
    if($Str=~/0\]\s*(.+)/) {
        return $1;
    }
    
    return undef;
}

sub findFiles(@)
{
    my ($Path, $Type) = @_;
    my $Cmd = "find \"$Path\"";
    
    if($Type) {
        $Cmd .= " -type ".$Type;
    }
    
    my @Res = split(/\n/, `$Cmd`);
    return @Res;
}

sub isHeader($)
{
    my $Path = $_[0];
    return ($Path=~/\.(h|hh|hp|hxx|hpp|h\+\+|tcc)\Z/i);
}

sub detectPublicSymbols($)
{
    my $Path = $_[0];
    
    if(not -e $Path) {
        exitStatus("Access_Error", "can't access \'$Path\'");
    }
    
    printMsg("INFO", "Detect public symbols");
    
    if(not check_Cmd($CTAGS))
    {
        printMsg("ERROR", "can't find \"$CTAGS\"");
        return;
    }
    
    my @Files = ();
    my @Headers = ();
    
    if(-f $Path)
    { # list of headers
        @Headers = split(/\n/, readFile($Path));
    }
    elsif(-d $Path)
    { # directory
        @Files = findFiles($Path, "f");
        
        foreach my $File (@Files)
        {
            if(isHeader($File)) {
                push(@Headers, $File);
            }
        }
    }
    
    foreach my $File (@Headers)
    {
        $PublicHeader{getFilename($File)} = 1;
    }
    
    #if(defined $OBJ_LANG and $OBJ_LANG eq "C")
    #{
        foreach my $File (@Headers)
        {
            my $HName = getFilename($File);
            my $IgnoreTags = "";
            
            if(defined $IgnoreTagsPath) {
                $IgnoreTags = "-I \@".$IgnoreTagsPath;
            }
            
            my $List_S = `$CTAGS -x --c-kinds=pfxv $IgnoreTags \"$File\"`;
            foreach my $Line (split(/\n/, $List_S))
            {
                if($Line=~/\A(\w+)/) {
                    $SymbolToHeader{$1} = $HName;
                }
            }
        }
    #}
    
    $PublicSymbols_Detected = 1;
}

sub scenario()
{
    if($Help)
    {
        HELP_MESSAGE();
        exit(0);
    }
    if($ShowVersion)
    {
        printMsg("INFO", "ABI Dumper $TOOL_VERSION");
        printMsg("INFO", "Copyright (C) 2015 Andrey Ponomarenko's ABI Laboratory");
        printMsg("INFO", "License: LGPL or GPL <http://www.gnu.org/licenses/>");
        printMsg("INFO", "This program is free software: you can redistribute it and/or modify it.\n");
        printMsg("INFO", "Written by Andrey Ponomarenko.");
        exit(0);
    }
    if($DumpVersion)
    {
        printMsg("INFO", $TOOL_VERSION);
        exit(0);
    }
    
    $Data::Dumper::Sortkeys = 1;
    
    if($SortDump) {
        $Data::Dumper::Sortkeys = \&dump_sorting;
    }
    
    if($SymbolsListPath)
    {
        if(not -f $SymbolsListPath) {
            exitStatus("Access_Error", "can't access file \'$SymbolsListPath\'");
        }
        foreach my $S (split(/\s*\n\s*/, readFile($SymbolsListPath))) {
            $SymbolsList{$S} = 1;
        }
    }
    
    if($VTDumperPath)
    {
        if(not -x $VTDumperPath) {
            exitStatus("Access_Error", "can't access \'$VTDumperPath\'");
        }
        
        $VTABLE_DUMPER = $VTDumperPath;
    }
    
    if(defined $Compare)
    {
        my $P1 = $ARGV[0];
        my $P2 = $ARGV[1];
        
        if(not $P1) {
            exitStatus("Error", "arguments are not specified");
        }
        elsif(not -e $P1) {
            exitStatus("Access_Error", "can't access \'$P1\'");
        }
        
        if(not $P2) {
            exitStatus("Error", "second argument is not specified");
        }
        elsif(not -e $P2) {
            exitStatus("Access_Error", "can't access \'$P2\'");
        }
        
        my %ABI = ();
        
        $ABI{1} = eval(readFile($P1));
        $ABI{2} = eval(readFile($P2));
        
        my %SymInfo = ();
        
        foreach (1, 2)
        {
            foreach my $ID (keys(%{$ABI{$_}->{"SymbolInfo"}}))
            {
                my $Info = $ABI{$_}->{"SymbolInfo"}{$ID};
                
                if(my $MnglName = $Info->{"MnglName"}) {
                    $SymInfo{$_}{$MnglName} = $Info;
                }
                elsif(my $ShortName = $Info->{"MnglName"}) {
                    $SymInfo{$_}{$ShortName} = $Info;
                }
            }
        }
        
        foreach my $Symbol (sort keys(%{$SymInfo{1}}))
        {
            if(not defined $SymInfo{2}{$Symbol}) {
                printMsg("INFO", "Removed $Symbol");
            }
        }
        
        foreach my $Symbol (sort keys(%{$SymInfo{2}}))
        {
            if(not defined $SymInfo{1}{$Symbol}) {
                printMsg("INFO", "Added $Symbol");
            }
        }
        
        exit(0);
    }
    
    if(not $TargetVersion) {
        printMsg("WARNING", "module version is not specified (-lver NUM)");
    }
    
    if($FullDump)
    {
        $AllTypes = 1;
        $AllSymbols = 1;
    }
    
    if(not $OutputDump) {
        $OutputDump = "./ABI.dump";
    }
    
    if(not @ARGV) {
        exitStatus("Error", "object path is not specified");
    }
    
    foreach my $Obj (@ARGV)
    {
        if(not -e $Obj) {
            exitStatus("Access_Error", "can't access \'$Obj\'");
        }
    }
    
    if($AltDebugInfo)
    {
        if(not -e $AltDebugInfo) {
            exitStatus("Access_Error", "can't access \'$AltDebugInfo\'");
        }
    }
    else
    {
        if(not check_Cmd($EU_READELF)) {
            exitStatus("Not_Found", "can't find \"$EU_READELF\" command");
        }
        foreach my $Obj (@ARGV)
        {
            my $Sect = `$EU_READELF_L -S \"$Obj\" 2>\"$TMP_DIR/error\"`;
    
            if($Sect=~/\.z?debug_info/)
            {
                if($Sect=~/\.gnu_debugaltlink/)
                {
                    if(my $AltDebugFile = getDebugFile($Obj, "gnu_debugaltlink"))
                    {
                        my $AltObj_R = getDirname($Obj)."/".$AltDebugFile;
                        
                        my $AltObj = $AltObj_R;
                        
                        while($AltObj=~s&/[^/]+/\.\./&/&){};
                        
                        if(-e $AltObj)
                        {
                            printMsg("INFO", "Set alternate debug-info file to \'$AltObj\' (use -alt option to change it)");
                            $AltDebugInfo = $AltObj;
                        }
                        else
                        {
                            printMsg("WARNING", "can't access \'$AltObj_R\'");
                        }
                    }
                }
                last;
            }
        }
    }
    
    if($AltDebugInfo) {
        read_Alt_Info($AltDebugInfo);
    }
    
    if($ExtraInfo)
    {
        mkpath($ExtraInfo);
        $ExtraInfo = abs_path($ExtraInfo);
    }
    
    init_ABI();
    
    my $Res = 0;
    
    foreach my $Obj (@ARGV)
    {
        $TargetName = getFilename(realpath($Obj));
        $TargetName=~s/\.debug\Z//; # nouveau.ko.debug
        
        if(index($TargetName, "libstdc++.so")==0) {
            $STDCXX_TARGET = 1;
        }
        
        read_Symbols($Obj);
        
        if(not defined $PublicSymbols_Detected)
        {
            if(defined $PublicHeadersPath) {
                detectPublicSymbols($PublicHeadersPath);
            }
        }
        
        $Res += read_DWARF_Info($Obj);
        
        %DWARF_Info = ();
        %ImportedUnit = ();
        %ImportedDecl = ();
        
        read_Vtables($Obj);
    }
    
    if(not $Res) {
        exitStatus("No_DWARF", "can't find debug info in object(s)");
    }
    
    %VirtualTable = ();
    
    complete_ABI();
    remove_Unused();
    
    %Mangled_ID = ();
    %Checked_Spec = ();
    %SelectedSymbols = ();
    %Cache = ();
    
    %ClassChild = ();
    %TypeSpec = ();
    
    # clean memory
    %SourceFile = ();
    %SourceFile_Alt = ();
    %DebugLoc = ();
    %TName_Tid = ();
    %TName_Tids = ();
    %SymbolTable = ();
    
    if(defined $PublicHeadersPath)
    {
        foreach my $H (keys(%HeadersInfo))
        {
            if(not defined $PublicHeader{getFilename($H)}) {
                delete($HeadersInfo{$H});
            }
        }
    }
    
    dump_ABI();
    
    exit(0);
}

scenario();
