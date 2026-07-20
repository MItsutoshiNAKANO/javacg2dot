#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Test::More;
use FindBin;

my $script = "$FindBin::Bin/../javacg2dot.pl";
if ( !do $script ) {
    die $@ || $OS_ERROR || 'unknown error loading script';
}

subtest 'parse_call_line' => sub {
    my ( $caller, $callee )
        = parse_call_line('M:class1:method1() (M)class2:method2()');
    is( $caller, 'class1:method1()', 'caller is parsed' );
    is( $callee, 'class2:method2()', 'callee is parsed' );

    my @excluded
        = parse_call_line('M:class1:method1() (M)java.lang.String:trim()');
    is( scalar @excluded, 0, 'a call to java.* is excluded' );

    my @unmatched = parse_call_line('this is not a call line');
    is( scalar @unmatched, 0, 'a non-matching line returns nothing' );

    return;
};

subtest 'class_of' => sub {
    is( class_of('org.example.Foo:bar()'),
        'org.example.Foo', 'an ordinary method resolves its class' );
    is( class_of('org.example.Foo:<init>(java.lang.String)'),
        'org.example.Foo',
        'a constructor <init> resolves its class (regression)'
    );
    is( class_of('org.example.Foo:<clinit>()'),
        'org.example.Foo',
        'a static initializer <clinit> resolves its class (regression)' );
    is( class_of('Outer$Inner:method()'),
        'Outer$Inner', 'an inner class name is preserved' );
    is( class_of('no-colon-here'),
        undef, 'a string without a colon has no class' );

    return;
};

subtest 'record_edge' => sub {
    my %state = ( edges => {}, callees => {}, callers => {} );
    is( record_edge( \%state, 'A:a()', 'B:b()' ),
        1, 'the first occurrence of an edge is recorded' );
    is( record_edge( \%state, 'A:a()', 'B:b()' ),
        0, 'a duplicate edge is not recorded again' );
    is_deeply( [ keys %{ $state{callees}{'B:b()'} } ],
        ['A:a()'], 'callees is populated exactly once' );
    is_deeply( [ keys %{ $state{callers}{'A:a()'} } ],
        ['B:b()'], 'callers is populated exactly once' );

    return;
};

subtest 'record_class_membership' => sub {
    my %state
        = ( classes => {}, callee_classes => {}, caller_classes => {} );
    record_class_membership( \%state,
        'org.example.Foo:<init>(java.lang.String)',
        'org.example.Bar:helper()' );
    ok( exists $state{classes}{'org.example.Foo'}
            {'org.example.Foo:<init>(java.lang.String)'},
        'a constructor is registered under its class (regression)'
    );
    ok( exists $state{classes}{'org.example.Bar'}
            {'org.example.Bar:helper()'},
        'a callee method is registered under its class'
    );

    return;
};

subtest 'end-to-end: constructors are clustered by class' => sub {
    my $fixture = "$FindBin::Bin/init_test.javacg-static.txt";
    my $dot     = qx{"$^X" "$script" "$fixture"};
    is( $CHILD_ERROR, 0, 'the script exits successfully' )
        or diag($dot);

    my ($foo_cluster) = $dot =~ m{
        subgraph \s "cluster_org\.example\.Foo" \s [{]
        (.*?)
        ^ [}]
    }xms;
    ok( defined $foo_cluster, 'the class org.example.Foo has a subgraph' )
        or diag($dot);
    like(
        $foo_cluster,
        qr{"org\.example\.Foo[.]<init>[(]java\.lang\.String[)]" \s [[][]][;]}xms,
        'the constructor <init> is inside its class subgraph'
    );
    like(
        $foo_cluster,
        qr{"org\.example\.Foo[.]<clinit>[(][)]" \s [[][]][;]}xms,
        'the static initializer <clinit> is inside its class subgraph'
    );

    unlike( $dot, qr{\bbar[(][)]}xms,
        'a caller whose only call target is java.* is dropped entirely' );
    unlike( $dot, qr{\btrim\b}xms,
        'a call into a java.* package is excluded from the output' );

    return;
};

done_testing();
