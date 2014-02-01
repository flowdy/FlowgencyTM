use strict;

package Util::TreeFromLazyStr;
use Moose;
use Moose::Util::TypeConstraints;
use Carp qw(croak);
 
=head1 NAME

Util::TreeFromLazyStr - Deserialize tree structures from quick notated strings

=head1 VERSION

Version 0.001 (i.e. draft/alpha - Please test, but do not use)

DRAFT/DELETE: Not ready for, I not even decided if this module should go for CPAN. In fact, it started as a utility module inside the FlowTime project (a time-management tool, so bloody alpha it is not even published yet, consider taskwarrior &co. for the time being) and is maybe not enough generalized for public use.

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
    default => sub { qr/ \A (\w+) (?: : \s* | \s+) /xms }
);

has sep_cache => (
    is => 'ro', isa => 'HashRef[SeparatorRegexp]',
    default => sub {{}},
);

sub _unescape ($) {
    $_[0] =~ s{ \\ ( [0x] [[:xdigit:]]{1,2} 
                   | \w (?: \{ ([^\}]+) \} )?
                   | . ) }{
      my $escaped = $1;
      # turn any backslash + newline into space
        "$escaped" eq "\n"  ? q/' '/      
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

    $num or return map { parse($self, $_, 1) } @parts;

    my ($twig, @leaves) = split /$isep(?=[^\d\s])/, shift @parts;
    
    croak "Unexpected separator in twig: $1 - possibly miscounted?"
        if $twig =~ $firstsep;

    my $list_sep   = $self->list_separator;
    my $key_extr   = $self->key_extractor;
    my %leaves;
    for my $leaf ( @leaves ) {
        croak "Unexpected separator in a leaf: $1 - possibly miscounted?"
            if $leaf =~ $firstsep;
        my $key = $leaf =~ s{$key_extr}{}xms ? $1
                : croak "Missing key in line \"$leaf\"";
        _unescape $leaf;
        my @val = split /$list_sep/, $leaf;
        $leaves{$key} = @val > 1 ? \@val : shift @val;
    }

    _unescape $twig;
    $twig = $self->create_twig->($twig, $parent, \%leaves);
    $_ = parse($self, $_, $num+1, $twig)     for @parts;
    $self->finish_twig->( \%leaves, @parts ) for $twig;

    return $twig;
}

__PACKAGE__->meta->make_immutable;
no Moose;

package main;
use Carp qw/croak/;

sub get_flowtime_task_parser {
    Util::TreeFromLazyStr->new({
        create_twig => \&parse_taskstep_title,
        finish_twig => sub { shift; $_->{substeps} = \@_ if @_; },
        @_
    });
}

sub parse_taskstep_title {
    my ($head, $parent, $leaves) = @_;

    my %data;

    # Recognize id string for the task/step
    if ( $head =~ s{ \s* = (\w+) }{}xms ) {
        $data{name} = $1;
    }

    # Recognize tags 
    if ( $head =~ s{ \s* \B \# (\p{Alpha}\w+) }{}xms ) {
        push @{$data{tags}}, $1;
    }

    # Recognize from-date, time track (or contiguous pairs of both) and the
    # deadline after all.
    my $date_rx = qr{\d[.\-\d]{,8}[\d.]\b};
    if ( $head =~
           s{ ( [a-z] \w+                   # id string of a time track (tp)
              | $date_rx                    # date to be parsed by Time::Point
              | (?:,?(?:$date_rx:[^,\s]+))+ # ","-sep. pairs of from-date and tp
              )? --? ($date_rx)             # deadline date
            }{}xms
    ) {

        my @components = split /,/, $1//q{};
        if ( @components > 1 ) {
            for ( split /,/, $1 ) {
                my ($date, $tplabel) = split /:/, $_;
                $data{timetrack_from}{$date} = $tplabel;
            }
        }
        elsif ( my $single = shift @components ) {
            if ( $single =~ /^\d/ ) {
                $data{timetrack_from}{$single} = "DEFAULT";
            }
            else {
                $data{timetrack} = $single;
            }
        }
    }
    
    return $head if !%data and $head =~ /^[a-z]\S+$/;

    $data{title} = $head;
    $data{parents_name} = $parent->{name} // '(anonymous parent)'
        if $parent;
    
    while ( my ($key, $leaf) = each %$leaves ) {
        croak "Key exists: $key" if exists $data{$key};
        $data{$key} = $leaf;
    }

    return \%data;

}

if ( @ARGV and $ARGV[0] eq 'test' ) {
    local $/ = "\n__END__"; eval <DATA>; die $@ if $@;
}

1;

__END__

$/ = "\n";
use Test::More;
use strict;

my $p = get_flowtime_task_parser();

is_deeply [ $p->parse('Dies ist einer ;0 Und das ein weiterer') ], [ { title => 'Dies ist einer' }, { title => 'Und das ein weiterer' } ], 'Zwei einfache Aufgaben (nur Titel)';

is_deeply $p->parse('Dies ist ein Task ;1 mit einem untergeordneten Step'), { title => 'Dies ist ein Task', substeps => [ { title => 'mit einem untergeordneten Step', parents_name => '(anonymous parent)' } ] }, 'Task mit untergeordnetem Step, Inline-Trenner';

is_deeply $p->parse("Man kann auch Newline benutzen: Dies ist ein Task\n1 mit einem untergeordneten Step"), { title => 'Man kann auch Newline benutzen: Dies ist ein Task', substeps => [ { title => 'mit einem untergeordneten Step', parents_name => '(anonymous parent)' } ] }, '... Trennung per Newline';

is_deeply $p->parse("Man kann auch Newline benutzen: Dies ist ein Task\n1mit einem untergeordneten Step"), { title => 'Man kann auch Newline benutzen: Dies ist ein Task', substeps => [ { title => 'mit einem untergeordneten Step', parents_name => '(anonymous parent)' } ] }, '... per Newline ohne Leerraum nach der Ziffer';

is_deeply $p->parse("Dies ist ein Task mit Deadline ;until 30.11.\n1und einem untergeordneten Step"), { title => 'Dies ist ein Task mit Deadline', until => '30.11.', substeps => [ { title => 'und einem untergeordneten Step', parents_name => '(anonymous parent)' } ] }, 'Task mit Attributblatt und untergeordnetem Step';

chomp(my $long_str = <<'EOS');
This is a task with a deadline ;until 30.11.
1and a subordinated step ;2 The whole thing is nestable in that\
many levels you want ;however: in a certain depth you'll find it not\
manageable any more ;1 We decrement in order to return to a higher level
;from 15.11.:bureau; 24.11.:labor
EOS

is_deeply $p->parse($long_str), {'substeps' => [{'substeps' => [{'title' => 'The whole thing is nestable in that many levels you want','parents_name' => '(anonymous parent)','however' => 'in a certain depth you\'ll find it not manageable any more'}],'title' => 'and a subordinated step','parents_name' => '(anonymous parent)'},{'from' => ['15.11.:bureau','24.11.:labor'],'title' => 'We decrement in order to return to a higher level','parents_name' => '(anonymous parent)'}],'until' => '30.11.','title' => 'This is a task with a deadline'}, "Langer String";


__END__

Weitere Tests hinzuzufügen:

#  $p = get_flowtime_task_parser()

#  x $p->parse("Hallo Welt!")                                                                             
0  HASH(0x3076aa8)
   'title' => 'Hallo Welt!'
#  x $p->parse("Hallo Welt! ;dies ist ein Attribut")
0  HASH(0x3184c90)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
#  x $p->parse("Hallo Welt!;dies ist ein Attribut")
0  HASH(0x32ac5b8)
   'title' => 'Hallo Welt!;dies ist ein Attribut'
#  x $p->parse("Hallo Welt! ;dies ist ein Attribut")
0  HASH(0x31845d0)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
#  x $p->parse("Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch hier?")
0  HASH(0x3255730)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
1  HASH(0x3255778)
   'title' => 'Hallo Mars, du auch hier?'
#  x $p->parse('Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch \;hier?')
0  HASH(0x3255760)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
1  HASH(0x319e480)
   'title' => 'Hallo Mars, du auch ;hier?'
#  x $p->parse('Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch ;hier, das ist ja Wahnsinn!')
Missing key in line "hier, das ist ja Wahnsinn!" at TreeFromLazyStr.pm line 220
#  x $p->parse('Hallo Welt! ;dies ist ein Attribut ;0 Hallo Mars, du auch ;hier , das ist ja Wahnsinn!')
0  HASH(0x323a720)
   'dies' => 'ist ein Attribut'
   'title' => 'Hallo Welt!'
1  HASH(0x3255c58)
   'hier' => ', das ist ja Wahnsinn!'
   'title' => 'Hallo Mars, du auch'
#  x $p->parse('Hallo Welt! \;dies ist ein Attribut ;0 Hallo Mars, du auch ;hier , das ist ja Wahnsinn!') 
0  HASH(0x319e7c8)
   'title' => 'Hallo Welt! ;dies ist ein Attribut'
1  HASH(0x3256b30)
   'hier' => ', das ist ja Wahnsinn!'
   'title' => 'Hallo Mars, du auch'
#  x $p->parse('Hallo Welt! \;dies ist ein Attr\033ibut ;0 Hallo Mars, du auch ;hier , das ist ja Wahnsinn!')
0  HASH(0x3184c90)
   'title' => "Hallo Welt! ;dies ist ein Attr\eibut"
1  HASH(0x3255718)
   'hier' => ', das ist ja Wahnsinn!'
   'title' => 'Hallo Mars, du auch'
#  x $p->parse('Ich escape einen Trenner\ ;1und habe Spaß daran')
0  HASH(0x2a5e7b8)
   'title' => 'Ich escape einen Trenner ;1und habe Spaß daran'
#  x $p->parse('Ich escape einen Trenner \;1und habe Spaß daran')
0  HASH(0x2b6cf40)
   'title' => 'Ich escape einen Trenner ;1und habe Spaß daran'
#  x $p->parse('Ich escape einen Trenner ;1und habe Spaß daran')
0  HASH(0x2c703b0)
   'substeps' => ARRAY(0x2b73268)
      0  HASH(0x2c3d880)
         'title' => 'und habe Spaß daran'
   'title' => 'Ich escape einen Trenner'
#  x $p->parse('Ich escape einen Trenner\  ;1und habe Spaß daran')
0  HASH(0x2e43688)
   'substeps' => ARRAY(0x2f58098)
      0  HASH(0x2f51f20)
         'title' => 'und habe Spaß daran'
   'title' => 'Ich escape einen Trenner '
#  x $p->parse('Ich escape einen Trenner\ \ ;1und habe Spaß daran')
0  HASH(0x2f511b8)
   'title' => 'Ich escape einen Trenner  ;1und habe Spaß daran'
#  $p = get_flowtime_task_parser(inline_sep_mark => '][')

#  p $p->inline_sep_mark
(?^:(?<!\\)\]\[)
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][, das geht genauso gut')  
0  HASH(0x37ba6e8)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x38c9c58)
   'title' => 'ich die Bestandteile hier mit ][, das geht genauso gut'
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit][das geht genauso gut')  
0  HASH(0x38c9718)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x397dcf0)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit'
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit\][ ][das geht genauso gut')  
0  HASH(0x39973e0)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x38e18e0)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit][ '
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit\][][das geht genauso gut')  
0  HASH(0x38c97f0)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3997a28)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut')  
0  HASH(0x38c96d0)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3997a10)
   'das' => 'geht genauso gut'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut][2Selbst ein Fehler wird artig geworfen, wenn ich mich verzähle')  
Unexpected separator in a leaf: 2 - possibly miscounted? at TreeFromLazyStr.pm line 184
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3997b30)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x39979c8)
   'das' => 'geht genauso gut'
   'substeps' => ARRAY(0x38ce4a8)
      0  HASH(0x38cdf68)
         'parents_name' => '(anonymous parent)'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die =Mama Bestandteile hier mit \][][das geht genauso gut][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3998158)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x39980c8)
   'das' => 'geht genauso gut'
   'name' => 'Mama'
   'substeps' => ARRAY(0x3998110)
      0  HASH(0x3997968)
         'parents_name' => 'Mama'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut ][name Mama][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3998f20)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3a06758)
   'das' => 'geht genauso gut '
   'name' => 'Mama'
   'substeps' => ARRAY(0x3998e78)
      0  HASH(0x39973f8)
         'parents_name' => 'Mama'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x3997938)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x3a06698)
   'das' => 'geht genauso gut'
   'substeps' => ARRAY(0x3a06728)
      0  HASH(0x3998ea8)
         'parents_name' => '(anonymous parent)'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
#  x $p->parse('Wie Sie sehen, trenne][0 ich die Bestandteile hier mit \][][das geht genauso gut ][name Mama][1Hier noch mal mit untergeordnetem Zeug')  
0  HASH(0x388fc58)
   'title' => 'Wie Sie sehen, trenne'
1  HASH(0x37ba6e8)
   'das' => 'geht genauso gut '
   'name' => 'Mama'
   'substeps' => ARRAY(0x3998f68)
      0  HASH(0x3997440)
         'parents_name' => 'Mama'
         'title' => 'Hier noch mal mit untergeordnetem Zeug'
   'title' => 'ich die Bestandteile hier mit ]['
done_testing;


=head2 Syntax overview

The number cannot separate the twigs barely, however, as that would mean you must have no other numbers in the string. It must therefore be prefixed with a certain string easy to remember: L< ;> by default, i.e. space (or more spaces) and semicolon. That prefix is customizable, so you could equally choose the pipe (vertical bar) or whatever. For customization you can either pass the separator as a string, then the module tries to apply a backslash escape point at an apropriate place in front. Or you pass a regex object (L<qr//>), but then you have to make sure you require a space or something in front of your regex object, else it might get ambiguous, error-prone at last. Instead of the prefix you can always prepend the number with one or more newlines.

Behind the number come a colon and/or space and then, up to the next separator, the twig string. You provide a callback (subroutine reference) that bootstraps from that string an object to return. How it does that, even whether the object is a dumb hash-ref or an object you manipulate by methods, whatever, that is completely up to you. The module implements a so-called I<push parser> that will not deal with the current node directly, it just calls the other routines you passed to the parser constructor to get hands dirty on that ominous tree object.
DRAFT/DELETE: In FlowTime, for instance, that callback routine extracts from the string some essential metadata compactly marked by one non-alphanumerical character, namely the deadline ('!date'), the id or id prefix ('=id'), and tags ('#tag') of the task to create. In a new anonymous hash it then predefines the respective keys and stuffs the rest into 'title' entry. The hash is passed to the Task constructor in the end.

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

