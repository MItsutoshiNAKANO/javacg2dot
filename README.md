# NAME

javacg2dot - Convert Java call graph to Graphviz DOT format

# SYNOPSIS

    javacg2dot.pl [OPTIONS] TARGET.javacg-static.txt ... >TARGET.dot
    Options:
        -f REGEX Specify a filter regex.
        --help Print a brief help message and exit.
        --version Print the version number and exit.

# USAGE

    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static.txt
    javacg2dot.pl -f 'some.package' TARGET.javacg-static.txt\
      >TARGET.dot
    dot -Tsvg -o TARGET.svg TARGET.dot

# REQUIRED ARGUMENTS

- `TARGET.javacg-static.txt`

    Java call graph in the format produced by
    [java-callgraph](https://github.com/gousiosg/java-callgraph) static.

# OPTIONS

- `-f REGEX` Specify a filter regex.

    REGEX is a Perl regular expression to filter the methods to be included in the
    output.
    REGEX is applied to both the caller and callee methods, and a method is
    included in the output if either the caller or callee matches the REGEX.
    REGEX is applied to the full method name, including the class name and the
    method signature, in the format of javacg-static output.
    REGEX is case-sensitive by default, but you can use the (?i) modifier to make
    it case-insensitive.
    REGEX style is Perl regular expression syntax, so you can use any valid Perl
    regex syntax, including character classes, quantifiers, anchors, and so on.
    REGEX modifiers are /xms by default, so you can use whitespace and comments in
    your regex, and the dot (.) matches any character.

- `--help` Print a brief help message and exit.
- `--version` Print the version number and exit.

# DESCRIPTION

This script reads a Java call graph in the format produced by
javacg-static and converts it into Graphviz DOT format for
visualization.

Classes and methods are sorted in ascending order by how many times
they are called, so that classes and methods called less often come
first. When two classes or methods are called the same number of
times, they are sorted in descending order by how many times they
call other classes or methods, so that classes and methods that call
more often come first among ties.

This sort order is intentional: Graphviz tends to place earlier
nodes toward the top of the rendered graph, so this ordering pushes
caller-side classes and methods toward the top of the output and
callee-side classes and methods toward the bottom. The resulting
top-to-bottom flow, from callers down to callees, is intended to make
the call graph easier to read.

# DIAGNOSTICS

- `Unknown option:`

    You specified an unknown option.
    Run the script with `--help` to see the available options.

- `invalid filter regex:`

    You specified an invalid filter regex.
    Run the script with `--help` to see the correct usage.

- `, so couldn't print`

    The script couldn't print due to output error.

# EXIT STATUS

The script exits with status 0 on success, and 1-255 if an error occurs.

# CONFIGURATION

This script does not use any configurations.

# DEPENDENCIES

- [java-callgraph](https://github.com/gousiosg/java-callgraph)
- [Perl](https://www.perl.org/)
- [Getopt::Std](https://perldoc.perl.org/Getopt/Std)
- [Carp](https://perldoc.perl.org/Carp)
- [English](https://perldoc.perl.org/English)
- [strict](https://perldoc.perl.org/strict)
- [warnings](https://perldoc.perl.org/warnings)
- [Graphviz](https://graphviz.org/)

# INCOMPATIBILITIES

This script is compatible with Perl 5.26.3 and later.

# BUGS AND LIMITATIONS

The output graph should be more readable/easier to understand.

# AUTHOR

Mitsutoshi NAKANO <ItSANgo@gmail.com>

# LICENSE AND COPYRIGHT

Copyright 2026 Mitsutoshi NAKANO

SPDX-License-Identifier: Apache-2.0
