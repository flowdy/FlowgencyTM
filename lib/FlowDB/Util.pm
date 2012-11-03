
package FlowDB::Util;
use base Exporter;
use Carp qw(croak);

our @EXPORT_OK = ('traverse');

=head1 UTILITIES for handling the FlowDB database model

=head2 traverse

Generic recursive traverser for graph objects. traverse() expects the following mandatory parameters:

=over 4

=item $node

The node object from where the traversal will start. The $node->can($get_subnode_list).

=item $get_subnode_list

$node->$get_subnode_list() must return one or more other instances of node's class, e.g. the descendents of a tree node. Practically, it must emit objects that can($get_subnode_list) as well.

=item $action

Reference to a subroutine that is assumed to do some meaningful aggregations of a node and $action()'s results of the direct descendents or whatever &$get_subnode_list emits. These are passed to it, headed by the current node, as a list of an anonymous array reference for each.

=item %options

Currently, only one option is supported: abortIfCircularRef. Its value can either be some true number (conventionally 1), then each traversed object is remembered and re-identified by its default perl stringification consisting of native type, class name and address in memory. Or you can provide the name or reference of a stringification or identifier method that is called on each node. It is passed no other arguments.

If you omit that option or provide a false value, no detection of circular references takes place. You will have to handle that case on your own or you must avoid it, otherwise perl might abort because of too many recursion levels. 

=back

=cut

sub traverse {
    my ($node, $get_subnode_list, $action, %options) = @_;

    my $circ_ref_check = do {
        my %refs = ();
        my $stringify = $options{abortIfCircularRef};
        return sub{0} if !$stringify;
        no warnings 'numeric'; # check stringiness w/o slow regex ...
        !(0+$stringify) ? sub { $refs{shift->$stringify()}++ }
                        : sub { $refs{$_[0]}++ }
                        ;
    };
                                                
    # we have to avoid memory leakage because of circular sub reference:
    # cf. http://rosettacode.org/wiki/Y_combinator#Perl
    my $Y = sub {
        my ($f) = @_;
        sub { my ($x) = @_; $x->($x) }->(
            sub {
                my ($y) = @_;
                $f->(
                    sub { $y->($y)->(@_) }
                )
            }
        );
    };

    my $called_recursively = sub {
        my ($Y_sub) = @_;
        sub {
            my $obj = shift;
            croak 'circular reference detected' if $circ_ref_check->($obj);
            $action->($obj, map {[ $Y_sub->($_) ]} $obj->$get_subnode_list() );
        }
    };

    return $Y->($called_recursively)->($obj);

}

1;
