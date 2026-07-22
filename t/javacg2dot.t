#! /usr/bin/env perl
use 5.026003;
use strict;
use warnings;
use Carp;
use English qw(-no_match_vars);
use Test::More;
use FindBin;
use File::Temp qw(tempfile);

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

    my @no_caller_class
        = parse_call_line('M:nocolonhere (M)class2:method2()');
    is( scalar @no_caller_class, 0,
        'a caller without a class separator : is rejected' );

    my @no_callee_class
        = parse_call_line('M:class1:method1() (M)nocolonhere');
    is( scalar @no_callee_class, 0,
        'a callee without a class separator : is rejected' );

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

subtest 'escape_method' => sub {
    my @result = escape_method('org.example.Foo:bar()');
    is_deeply(
        \@result,
        [ 'org.example.Foo.bar()', 'bar()' ],
        'returns the dotted class.method label and the bare method name'
    );

    my @quoted = escape_method(q{org.example.Foo:say("hi")});
    is_deeply(
        \@quoted,
        [ q{org.example.Foo.say(\"hi\")}, q{say(\"hi\")} ],
        'a double quote is escaped in both elements'
    );

    my @backslash = escape_method('Foo:bar(\)');
    is_deeply(
        \@backslash,
        [ 'Foo.bar(\\\\)', 'bar(\\\\)' ],
        'a backslash is escaped in both elements'
    );

    my @invalid = escape_method('no-colon-here');
    is( scalar @invalid, 0,
        'a string without a colon returns nothing' );

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

subtest 'load_javacg_static with a filter regex' => sub {
    my ( $fh, $filename ) = tempfile();
    print {$fh} <<'_END_OF_FIXTURE_' or die $OS_ERROR;
M:keep.Caller:foo() (M)other.Callee:bar()
M:other.Caller:foo() (M)keep.Callee:bar()
M:other.Caller2:foo() (M)other.Callee2:bar()
_END_OF_FIXTURE_
    close $fh or die $OS_ERROR;

    local @ARGV = ($filename);
    local $ARGV;
    my $state = load_javacg_static(qr/keep/xms);
    my @callees = sort keys %{ $state->{edges} };
    is_deeply(
        \@callees,
        [ 'keep.Callee:bar()', 'other.Callee:bar()' ],
        'an edge is kept if either the caller or the callee matches'
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
        qr{"org\.example\.Foo[.]<init>[(]java\.lang\.String[)]" \s
            [[]label="<init>[(]java\.lang\.String[)]"[]][;]}xms,
        'the constructor <init> is inside its class subgraph'
    );
    like(
        $foo_cluster,
        qr{"org\.example\.Foo[.]<clinit>[(][)]" \s [[]label="<clinit>[(][)]"[]][;]}xms,
        'the static initializer <clinit> is inside its class subgraph'
    );

    unlike( $dot, qr{\bbar[(][)]}xms,
        'a caller whose only call target is java.* is dropped entirely' );
    unlike( $dot, qr{\btrim\b}xms,
        'a call into a java.* package is excluded from the output' );

    return;
};

subtest 'end-to-end: -f filters edges by caller or callee' => sub {
    my $fixture = "$FindBin::Bin/init_test.javacg-static.txt";
    my $dot     = qx{"$^X" "$script" -f "Baz" "$fixture"};
    is( $CHILD_ERROR, 0, 'the script exits successfully' )
        or diag($dot);

    like(
        $dot,
        qr{"org\.example\.Foo[.]<clinit>[(][)]" \s -> \s
            "org\.example\.Baz[.]init[(][)]" [;]}xms,
        'an edge whose callee matches the filter is kept'
    );
    unlike( $dot, qr{\bhelper\b}xms,
        'an edge whose caller and callee both fail to match the filter is dropped'
    );
    unlike( $dot, qr{"org\.example\.Foo[.]<init>}xms,
        'a dropped edge does not register its caller class membership' );

    return;
};

subtest 'end-to-end: same-named methods stay distinct per class' => sub {
    my ( $fh, $filename ) = tempfile();
    print {$fh} <<'_END_OF_FIXTURE_' or die $OS_ERROR;
M:pkg.A:run() (M)pkg.Target:common()
M:pkg.B:run() (M)pkg.Target:common()
_END_OF_FIXTURE_
    close $fh or die $OS_ERROR;

    my $dot = qx{"$^X" "$script" "$filename"};
    is( $CHILD_ERROR, 0, 'the script exits successfully' )
        or diag($dot);

    like(
        $dot,
        qr{"pkg\.A[.]run[(][)]" \s -> \s "pkg\.Target[.]common[(][)]" [;]}xms,
        'the edge from pkg.A.run() is kept distinct'
    );
    like(
        $dot,
        qr{"pkg\.B[.]run[(][)]" \s -> \s "pkg\.Target[.]common[(][)]" [;]}xms,
        'the edge from pkg.B.run() is kept distinct'
    );
    like(
        $dot,
        qr{"pkg\.A[.]run[(][)]" \s [[]label="run[(][)]"[]][;]}xms,
        'the node for pkg.A.run() is labeled with just the method name'
    );
    like(
        $dot,
        qr{"pkg\.B[.]run[(][)]" \s [[]label="run[(][)]"[]][;]}xms,
        'the node for pkg.B.run() is labeled with just the method name'
    );

    return;
    };

subtest 'end-to-end: -f rejects an invalid regex' => sub {
    my $fixture = "$FindBin::Bin/init_test.javacg-static.txt";
    my $stderr  = qx{"$^X" "$script" -f "(unclosed" "$fixture" 2>&1 1>/dev/null};
    isnt( $CHILD_ERROR, 0, 'the script exits with an error' );
    like(
        $stderr,
        qr{invalid \s filter \s regex}xms,
        'the error message names the problem'
    );

    return;
};

done_testing();
