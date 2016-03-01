use strict;

package FTM::FlowDB;
use base qw/DBIx::Class::Schema/;
use Carp qw/croak/;

__PACKAGE__->load_classes(qw|User Mailoop|,
    eval { FTM::User->does("FTM::User::Proxy") }
       ? ()
       : qw|Task Step TimeStage|
);

sub import {
    my ($class, $dbh_ref, $filename) = @_;
    return if @_ == 1;
    croak "use FTM::FlowDB \$your_db_handle missing" if !defined $dbh_ref;
    $$dbh_ref = $class->connect( $filename );
}

my $first_dsn;
sub connect {
    my ($class,$dsn,%args) = @_;
    my $deploy;

    if ( defined( $dsn //= $first_dsn ) ) {
        $dsn =~ s{ \A (?!DBI:) }{DBI:SQLite:}ixms;
        $first_dsn //= $dsn;
        $deploy = delete $args{deploy} // !(-e $_[1]);
    }
    else { $deploy = 1; $dsn = 'DBI:SQLite::memory:' }

    my @credentials = @{delete $args{credentials} // ['',''] };
    my $db = $class->SUPER::connect($dsn, @credentials, {
        sqlite_unicode => 1,
        on_connect_call => 'use_foreign_keys',
        %args
    });

    if ( $deploy ) {
        print "Deploying new database in ", $_[1] || "memory", "\n";
        $db->deploy();
    }

    return $db;

}

1;
