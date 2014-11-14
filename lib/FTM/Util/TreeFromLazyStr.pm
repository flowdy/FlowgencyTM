use strict;

package FTM::Util::TreeFromLazyStr;
use Moose;
use Moose::Util::TypeConstraints;
use Carp qw(croak);
 
my $NoBS = '(?<!\\\)'; # assert backslash in front

subtype 'SeparatorRegexp',
    as 'RegexpRef',
    where { "" =~ /|$_[0]/ and not $#+ },
    message { "A separator pattern must not capture anything" }
;

coerce 'SeparatorRegexp',
    from 'Str',
    via {
        return qr{$_} if  /\\Q/ || /\\E/;
        s{( (?: \\[st] | [ 	] ) [+*?]* | )}{}xms;
        return qr{$NoBS$1\Q$_\E};
    }
;

has [qw/create_twig finish_twig /] => (
    is => 'ro',  isa => 'CodeRef', required => 1
);

has inline_sep_mark => (
    is => 'ro', isa => 'SeparatorRegexp',
    coerce => 1, default => sub { qr/$NoBS\s+;/ }
);

has list_separator => (
    is => 'ro', isa => 'SeparatorRegexp',
    coerce => 1, default => sub { qr/$NoBS\s*;\s+/ }
);

has key_extractor => (
    is => 'ro', isa => 'RegexpRef',
    default => sub { qr/ \A (\w+) (?: $ | : \s* | \s+) /xms }
);

has sep_cache => (
    is => 'ro', isa => 'HashRef[SeparatorRegexp]',
    default => sub {{}},
);

has allowed_leaf_keys => (
    is => 'ro', isa => 'ArrayRef[Str]', auto_deref => 1, default => sub{[]},
    predicate => 'has_fields',
);

has leaf_key_aliases => (
    is => 'ro', isa => 'HashRef[Str]', auto_deref => 1, default => sub {{}}
);

sub _unescape ($) {
    $_[0] =~ s{ \\ ( [0x] [[:xdigit:]]{1,2} 
                   | \w (?: \{ ([^\}]+) \} )?
                   | . ) }{
      my $escaped = $1;
      # turn any backslash + newline into space
        "$escaped" eq "\n"  ? q/' '/      
      # resolve backslash
      : $escaped eq "\\"  ? qq/"\\\\"/
      # resolve alphanumeric escapes, possibly with extension
      : "$escaped" =~ /^\w/ ? qq/"\\$escaped"/  
      # resolve the rest escaped not to be detected as separator
      :                       qq/"$escaped"/    
    }eegxms;
}

sub parse {
    my ($self, undef, $num, $parent) = @_;
    $num //= wantarray ? 0 : 1;

    croak "second argument is not an integer"
        if defined $num and $num !~ /^\d+\z/;

    my $isep = $self->inline_sep_mark;
    my $c = $self->sep_cache;
    my ($fullsep, $firstsep) = map {
        $c->{$_} //= qr{ (?:(?:$NoBS\n)*^|$isep) $_ :? \s* }xms
      } $num, '(\d+)'
    ;

    my @parts = split /$fullsep/, $_[1];
    chomp @parts;

    $num or return map { parse($self, $_, 1) } @parts;

    my ($twig, @leaves) = split /$isep(?=[^\d\s])/, shift @parts;
    
    croak "Unexpected separator in twig: $1 - possibly miscounted?"
        if $twig =~ $firstsep;

    my $list_sep   = $self->list_separator;
    my $key_extr   = $self->key_extractor;
    my $fields     = $self->allowed_leaf_keys;
    my $aliases    = $self->leaf_key_aliases;

    my $key_resolver = sub {
        my $short = shift;
        if ( my $alias = $aliases->{$short} ) { return $alias; }
        else {
            my @fields = grep { m{ \A \Q$short\E }xms } @$fields;
            if ( @fields == 1 ) { return $aliases->{$short} = $fields[0]; }
            elsif ( !@fields ) {
                croak "key $short is unknown" if $self->has_fields;
                return $short;
            }
            else {
                croak "Key prefix $short ambiguously matches: ",
                    join q{ or }, @fields
            }
        }
    };

    my %leaves;
    for my $leaf ( @leaves ) {
        croak "Unexpected separator in a leaf: $1 - possibly miscounted?"
            if $leaf =~ $firstsep;
        my $key = $leaf =~ s{$key_extr}{}xms ? $1
                : croak "Missing key in line \"$leaf\"";
        $key = $key_resolver->($key);
        _unescape $leaf;
        my @val = split /$list_sep/, $leaf;
        $leaves{$key} = @val > 1 ? \@val : $val[0];
    }

    _unescape $twig;
    $twig = $self->create_twig->($twig, $parent, \%leaves);
    $_ = parse($self, $_, $num+1, $twig)     for @parts;
    $self->finish_twig->( \%leaves, @parts ) for $twig;

    return $twig;

}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::Util::TreeFromLazyStr - Deserialize tree structures from quick notated strings

=head1 VERSION

Version 0.001 (i.e. draft/alpha - Please test, but do not use productively)

DRAFT/DELETE: Not ready for, I not even decided if this module should go for CPAN. In fact, it started as a utility module inside the FlowgencyTM project (a time-management tool, so bloody alpha it is not even published yet, consider taskwarrior &co. for the time being) and is maybe not enough generalized for public use.

=head1 WHAT THIS MODULE PROVIDES 

=over 4

=item *

A customizable leaves-to-root (bottom-up) parser

=item *

for manageable monohierarchical tree structures

=item *

input by either someone of whom you cannot expect or who is fed up with hand-coding raw data from scratch

=item *

that is, input in a painless and quick, ad-hoc way

=item *

while learning it bit by bit instead of not understanding it all at once

=back

It relies on a backend sufficiently fault-tolerant in respect to processing the returned data, i.e. content-based validation is beyond the scope of this module.

=head1 WHY YET ANOTHER SERIALIZATION FORMAT?

What is the benefit of using Util::TreeFromLazyStr compared with JSON, YAML or XML?

The notation is optimized for a minimum of syntactic structurals. Nesting is neither indicated by brackets or tags of any kind which would need your caring for balance, nor by indentation that would require you to start every line with as many spaces or tabs as the current depth is, which is a rather boring and error-prone thing to do where auto-indenting facilities are missing (e.g. web form). Last but not least, quoting and escaping literal quotes is obsolete as well when using this module.

Basically, the difference between indentation and our approach is that you notate the current depth with an B<explicit number>. With plain numbers, at least those from 1 to 9, the human brain deals much easier than with balanced chains of parens, paths of nested tags or couples of invisible indentation characters. This proposition is the main rationale of this module and is to me worth a proof.

=head2 An example

 This is a task with a deadline ;until 30.11.
 1and a subordinated step ;2 The whole thing is nestable in that\
 many levels you want ;however: in a certain depth you'll find it not\
 manageable any more ;1 We decrement in order to return to a higher level
 ;from 15.11.:bureau; 24.11.:labor

=cut


=head2 Syntax overview

The number cannot separate the twigs barely, however, as that would mean you must have no other numbers in the string. It must therefore be prefixed with a certain string easy to remember: L< ;> by default, i.e. space (or more spaces) and semicolon. That prefix is customizable, so you could equally choose the pipe (vertical bar) or whatever. For customization you can either pass the separator as a string, then the module tries to apply a backslash escape point at an apropriate place in front. Or you pass a regex object (L<qr//>), but then you have to make sure you require a space or something in front of your regex object, else it might get ambiguous, error-prone at last. Instead of the prefix you can always prepend the number with one or more newlines.

Behind the number come a colon and/or space and then, up to the next separator, the twig string. You provide a callback (subroutine reference) that bootstraps from that string an object to return. How it does that, even whether the object is a dumb hash-ref or an object you manipulate by methods, whatever, that is completely up to you. The module implements a so-called I<push parser> that will not deal with the current node directly, it just calls the other routines you passed to the parser constructor to get hands dirty on that ominous tree object.
DRAFT/DELETE: In FlowgencyTM, for instance, that callback routine extracts from the string some essential metadata compactly marked by one non-alphanumerical character, namely the deadline ('!date'), the id or id prefix ('=id'), and tags ('#tag') of the task to create. In a new anonymous hash it then predefines the respective keys and stuffs the rest into 'title' entry. The hash is passed to the FTM::Task constructor in the end.

When the number of the next separator is equal to the previous, another twig string on the same level and, for n > 0, with the same parent is assumed. When it is incremented by one, the following twig is regarded as first descendent of the previous twig. Is the number incremented by more than one, it is probably a counting error and the parse will fail. By decrementing one or more you can climb up by that many levels and continue adding child nodes there.

In front of any numbered separators you can use B<key separators> followed by a value. This is a leaf, to be consequent in botanic terms. The above separator prefix is re-used for this, just instead of a number a letter-initial string must follow without space in between. That string is used as the attribute key. Key and value is passed to your callback for attribute registration.

In your custom C<finish_twig> callback, triggered after bootstrapping and completing the descendents, you choose to gather and define the attributes of the current node before and/or after mounting the direct subtwigs in a bulk. While a descendent is parsed and set up, it sees the parent node in freshly bootstrapped state only, i.e. without descendents defined earlier.

Note by the way that you must call the parse() method in list context if you want to support parsing multiple ' ;0'-separated root twigs at once. Parsing them in scalar context will result in an error.

Last but not least, leaves can have more than one value. Multiple values are L<; >-separated by default. Compared to default numbered and key separators, please note the reversed order of the semicolon and the mandatory space. Any space before them is optional.

From the explanation I hope you to get a clue of the data structure that results from parsing the example above:

 0  HASH(0x26be940)
   'substeps' => ARRAY(0x26745a8)
      0  HASH(0x26c4c48)
         'substeps' => ARRAY(0x26cb4a0)
            0  HASH(0x26c5458)
               'however' => 'in a certain depth you\'ll find it not manageable any more'
               'title' => 'The whole thing is nestable in that many levels you want'
         'title' => 'and a subordinated step'
      1  HASH(0x26cba10)
         'from' => ARRAY(0x1666f90)
            0  '15.11.:bureau'
            1  '24.11.:labor'
         'title' => 'We decrement in order to return to a higher level'
   'title' => 'This is a task with a deadline'
   'until' => '30.11.'

=head2 How about serialization?

Serialization and round-trip safety is not in scope of this module. If you need a format to have machines communicate in, other ones like e.g. those mentioned above might be more appropriate. Util::TreeFromLazyStr just makes it easy for humans to input nested data structures according the I<head and attributes> pattern.

=head1 COPYRIGHT

(C) 2012-2014 Florian Hess

=head1 LICENSE

This file is part of FlowgencyTM.

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

