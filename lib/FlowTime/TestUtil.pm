#!perl
use strict;
use warnings;

package FlowTime::TestUtil;
use base "Exporter";
use Test::More;
our @EXPORT = our @EXPORT_OK = qw(run_tests);

sub run_tests {
    my @args  = @_;
 
    my $pkg = caller;

    if (@args) {
        for my $name (@args) {
            die "No test method test_$name\n"
                unless my $func = $pkg->can( 'test_' . $name );
            $func->();
        }

        done_testing;
        return 0;
    }

    no strict 'refs';
    $pkg .= "::";
    &{$pkg.$_}() for grep /^test_/, keys %{$pkg}; 
         
    done_testing;
    return 0;
}

1;

