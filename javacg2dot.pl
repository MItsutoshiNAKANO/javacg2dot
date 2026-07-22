#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Getopt::Std;

our $VERSION = '0.1.2';

my $help_message = <<"_END_OF_HELP_";
Usage: $PROGRAM_NAME [OPTIONS] TARGET.javacg-static ... >TARGET.dot
Convert Java call graph to Graphviz DOT format.
Options:
    -f REGEX Specify a filter regex.
      REGEX is a Perl regular expression to filter the methods to be included
      in the output.
      REGEX is applied to both the caller and callee methods, and a method
      is included in the output if either the caller or callee matches
      the REGEX.
      REGEX is applied to the full method name, including the class name and
      the method signature, in the format of javacg-static output.
      REGEX is case-sensitive by default, but you can use the (?i) modifier to
      make it case-insensitive.
      REGEX style is Perl regular expression syntax, so you can use any valid
      Perl regex syntax, including character classes, quantifiers, anchors,
      and so on.
      REGEX modifiers are /xms by default, so you can use whitespace
      and comments in your regex, and the dot (.) matches any character.
example:
    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static
    $PROGRAM_NAME -f example.package TARGET.javacg-static >TARGET.dot
    dot -Tsvg -o TARGET.svg TARGET.dot

For more details run
    perldoc -F $PROGRAM_NAME
_END_OF_HELP_

##
# Print the help message.
sub HELP_MESSAGE {
    print "$help_message"
        or croak $OS_ERROR . q{, so couldn't print the help message};
    return $help_message;
}

##
# Parse a line of javacg-static output.
# @param[in] $line A line string of javacg-static output.
# @return
#   ($caller, $callee)
#   if the line represents a call, otherwise undef.
sub parse_call_line {
    my ($line) = @_;
    if ( $line =~ /\A M:(\S+:\S+)\s+ [(].[)](\S+:\S+)/xms ) {
        my ( $caller, $callee ) = ( $1, $2 );
        return if $callee =~ m/\Ajavax?[.]/xms;
        return ( $caller, $callee );
    }
    return;
}

##
# Return the class name of a method.
# @param[in] $method
#   A method string in the format of javacg-static output.
# @return
#   The class name of the method,
#   or undef if the method string is invalid.
sub class_of {
    my ($method) = @_;
    return $method =~ m/\A([^:]+):\S+/xms ? $1 : undef;
}

##
# Escape a string for use inside a DOT quoted string.
# @param[in] $string A string to escape.
# @return The string, with '"' and '\' backslash-escaped.
sub escape_string {
    my ($string) = @_;
    $string =~ s/(["\\])/\\$1/gxms;
    return $string;
}

##
# Escape a method string for use as a DOT node label.
# @param[in] $method
#   A method string in the format of javacg-static output.
# @return
#   A list of two elements:
#   1. The method string, escaped for DOT.
#   2. The method name, escaped for DOT.
#   or undef if the method string is invalid.
sub escape_method {
    my ($method) = @_;
    $method = escape_string($method);
    if ( $method =~ /\A([^:]+):(\S+)/xms ) {
        return ( $1 . q{.} . $2, $2 );
    }
    return;
}

##
# Record the class membership of the caller and callee methods.
# @param[out] $state
#   A hash reference to store the state of the call graph.
# @param[in] $caller
#   The caller method string in the format of javacg-static output.
# @param[in] $callee
#   The callee method string in the format of javacg-static output.
# @return
#   1 if the class membership was recorded successfully, otherwise 0.
sub record_class_membership {
    my ( $state, $caller, $callee ) = @_;

    if ( my $callee_class = class_of($callee) ) {
        $state->{callee_classes}{$callee_class}{$callee} = 1;
        $state->{classes}{$callee_class}{$callee}        = 1;
    }
    if ( my $caller_class = class_of($caller) ) {
        $state->{caller_classes}{$caller_class}{$caller} = 1;
        $state->{classes}{$caller_class}{$caller}        = 1;
    }
    return 1;
}

##
# Record the edge from caller to callee in the state.
# @param[out] $state
#   A hash reference to store the state of the call graph.
# @param[in] $caller
#   The caller method string in the format of javacg-static output.
# @param[in] $callee
#   The callee method string in the format of javacg-static output.
# @return 1 if the edge was recorded successfully, otherwise 0.
sub record_edge {
    my ( $state, $caller, $callee ) = @_;
    return 0 if ++$state->{edges}{$callee}{$caller} > 1;

    $state->{callees}{$callee}{$caller} = 1;
    $state->{callers}{$caller}{$callee} = 1;
    return 1;
}

##
# Load the javacg-static output and build the state.
# @param[in] $filter_regex
#   An optional regex to filter the methods to be included in the output.
# @return A hash reference containing the state of the call graph.
sub load_javacg_static {
    my ($filter_regex) = @_;

    ##
    # Initialize the state hash with empty structures for
    # edges, classes, callees, callee_classes, callers,
    # and caller_classes.
    # @param[out] edges
    #  A hash reference to store the edges of the call graph.
    # @param[out] classes
    #  A hash reference to store the classes and their methods.
    # @param[out] callees
    #  A hash reference to store the callees of each method.
    # @param[out] callee_classes
    #  A hash reference to store the classes of the callees.
    # @param[out] callers
    #  A hash reference to store the callers of each method.
    # @param[out] caller_classes
    #  A hash reference to store the classes of the callers.
    my %state = (
        edges          => {},
        classes        => {},
        callees        => {},
        callee_classes => {},
        callers        => {},
        caller_classes => {},
    );

    while (<>) {
        chomp;
        my ( $caller, $callee ) = parse_call_line($_);
        next if !defined $caller;
        next
            if defined $filter_regex
            && $caller !~ $filter_regex
            && $callee !~ $filter_regex;
        next if !record_edge( \%state, $caller, $callee );
        record_class_membership( \%state, $caller, $callee );
    }
    return \%state;
}

##
# Print the DOT graph header.
# @return 1 if the header was printed successfully, otherwise croak.
sub print_head {
    print <<~'_END_OF_HEAD_'
    digraph Call_Graph {
      node [shape=box];
    _END_OF_HEAD_
        or croak $OS_ERROR . q{, so couldn't print the head};
    return 1;
}

##
# Print the classes and their methods as subgraphs.
# @param[in] $parsed
#   A hash reference containing the parsed state of the call graph.
# @return
#   1 if the classes were printed successfully, otherwise croak.
sub print_classes {
    my ($parsed)       = @_;
    my %classes        = %{ $parsed->{classes} };
    my %callee_classes = %{ $parsed->{callee_classes} };
    my %caller_classes = %{ $parsed->{caller_classes} };
    my %callees        = %{ $parsed->{callees} };
    my %callers        = %{ $parsed->{callers} };

    my @sorted_classes = sort {
        keys %{ $callee_classes{$a} } <=> keys %{ $callee_classes{$b} }
            || -(
                keys %{ $caller_classes{$a} } <=>
                keys %{ $caller_classes{$b} } )
            || $a cmp $b
    } keys %classes;

    foreach my $class (@sorted_classes) {
        $class = escape_string($class);
        print <<~"_END_OF_SUBGRAPH_HEAD_"
          subgraph "cluster_$class" {
            label = "$class";
        _END_OF_SUBGRAPH_HEAD_
            or croak $OS_ERROR . q{, so couldn't print the subgraph head};

        my @sorted_methods = sort {
                   keys %{ $callees{$a} } <=> keys %{ $callees{$b} }
                || -( keys %{ $callers{$a} } <=> keys %{ $callers{$b} } )
                || $a cmp $b
        } keys %{ $classes{$class} };
        foreach my $method (@sorted_methods) {
            my ( $escaped, $shrunk ) = escape_method($method);
            say q{    "} . $escaped . q{" [label="} . $shrunk . q{"];}
                or croak $OS_ERROR . q{, so couldn't print the method};
        }
        say '  }'
            or croak $OS_ERROR . q{, so couldn't print the subgraph tail};
    }
    return 1;
}

##
# Print the edges between methods.
# @param[in] $parsed
#   A hash reference containing the parsed state of the call graph.
# @return
#   1 if the edges were printed successfully, otherwise croak.
sub print_edges {
    my ($parsed) = @_;
    my %edges = %{ $parsed->{edges} };

    my @sorted_callees
        = sort { keys %{ $edges{$a} } <=> keys %{ $edges{$b} } || $a cmp $b }
        keys %edges;
    foreach my $callee (@sorted_callees) {
        my ($escaped_callee) = escape_method($callee);
        foreach my $caller ( keys %{ $edges{$callee} } ) {
            my ($escaped_caller) = escape_method($caller);
            say q{  "}
                . $escaped_caller
                . q{" -> "}
                . $escaped_callee . q{";}
                or croak $OS_ERROR . q{, so couldn't print the edge};
        }
    }
    return 1;
}

##
# Print the DOT graph tail.
# @return 1 if the tail was printed successfully, otherwise croak.
sub print_tail {
    say '}' or croak $OS_ERROR . q{, so couldn't print the tail};
    return 1;
}

##
# Main function to execute the script.
# @return 1 if the script executed successfully, otherwise croak.
sub main {
    $Getopt::Std::STANDARD_HELP_VERSION = 1;
    getopts( 'f:', \my %opts ) or croak $help_message;
    my $filter_regex;
    if ( defined $opts{f} ) {
        eval { $filter_regex = qr/$opts{f}/xms }
            or croak 'invalid filter regex: ' . $opts{f} . "\n" . $EVAL_ERROR;
    }

    my $parsed = load_javacg_static($filter_regex);

    print_head();
    print_classes($parsed);
    print_edges($parsed);
    return print_tail();
}

if ( !caller ) { main() }

1;

__END__

=encoding utf8

=head1 NAME

javacg2dot.pl - Convert Java call graph to Graphviz DOT format

=head1 SYNOPSIS

    javacg2dot.pl [OPTIONS] TARGET.javacg-static ... >TARGET.dot
    Options:
        -f REGEX Specify a filter regex.
        --help Print a brief help message and exit.
        --version Print the version number and exit.

=head1 USAGE

    java -jar javacg-static.jar TARGET.jar >TARGET.javacg-static
    javacg2dot.pl -f 'some.package' TARGET.javacg-static >TARGET.dot
    dot -Tsvg -o TARGET.svg TARGET.dot

=head1 REQUIRED ARGUMENTS

=over

=item * F<TARGET.javacg-static>

Java call graph in the format produced by
L<java-callgraph|https://github.com/gousiosg/java-callgraph> static.

=back

=head1 OPTIONS

=over

=item * C<-f REGEX> Specify a filter regex.

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

=item * C<--help> Print a brief help message and exit.

=item * C<--version> Print the version number and exit.

=back

=head1 DESCRIPTION

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

Each method is rendered as a node whose DOT identifier is the full
C<class.method> name, so that edges between methods of the same name
in different classes stay unambiguous. Since the class is already
shown by the surrounding subgraph's cluster label, the node's visible
label is shortened to just the method name, keeping the rendered
graph less cluttered.

=head1 DIAGNOSTICS

=over

=item * C<Unknown option:>

You specified an unknown option.
Run the script with C<--help> to see the available options.

=item * C<invalid filter regex:>

You specified an invalid filter regex.
Run the script with C<--help> to see the correct usage.

=item * C<, so couldn't print>

The script couldn't print due to output error.

=back

=head1 EXIT STATUS

The script exits with status 0 on success, and 1-255 if an error occurs.

=head1 CONFIGURATION

This script does not use any configurations.

=head1 DEPENDENCIES

=over

=item * L<java-callgraph|https://github.com/gousiosg/java-callgraph>

=item * L<Perl|https://www.perl.org/>

=item * L<Getopt::Std|https://perldoc.perl.org/Getopt/Std>

=item * L<Carp|https://perldoc.perl.org/Carp>

=item * L<English|https://perldoc.perl.org/English>

=item * L<strict|https://perldoc.perl.org/strict>

=item * L<warnings|https://perldoc.perl.org/warnings>

=item * L<Graphviz|https://graphviz.org/>

=back

=head1 INCOMPATIBILITIES

This script is compatible with Perl 5.26.3 and later.

=head1 BUGS AND LIMITATIONS

Large graphs remain hard to read because they produce too many clusters.

=head1 AUTHOR

Mitsutoshi NAKANO <ItSANgo@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright 2026 Mitsutoshi NAKANO

SPDX-License-Identifier: Apache-2.0
