use strict;

package FlowDB;
use base qw/DBIx::Class::Schema/;

__PACKAGE__->load_classes(qw|User Task Step TimeLine|);

sub import {
    my ($class, $dbh_ref, $filename) = @_;
    return if !defined $dbh_ref;

    $filename ||= ':memory:';

    $$dbh_ref = FlowDB->connect(
    "DBI:SQLite:$filename", '', '',
        {
           sqlite_unicode => 1,
           use_foreign_keys => 1,
        }
    );

    if ( !$_[2] ) { $$dbh_ref->deploy }

}

1;
