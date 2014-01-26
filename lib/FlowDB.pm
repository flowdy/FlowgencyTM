use strict;

package FlowDB;
use base qw/DBIx::Class::Schema/;
use Carp qw/croak/;

__PACKAGE__->load_classes(qw|User Task Step TimeSegment|);

sub import {
    my ($class, $dbh_ref, $filename) = @_;
    croak "use FlowDB \$your_db_handle missing" if !defined $dbh_ref;

    $filename ||= ':memory:';

    $$dbh_ref = FlowDB->connect(
    "DBI:SQLite:$filename", '', '',
        {
           sqlite_unicode => 1,
           on_connect_call => 'use_foreign_keys',
        }
    );

    if ( !($filename && -e $filename) ) {
        print "Deploying new database in ", $filename || "memory", "\n";
        $$dbh_ref->deploy;
    }

}

1;
