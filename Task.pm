#!perl
use strict;

package Task;
use Carp qw(carp croak);

sub new { # traditional style constructor to avoid dependencies
          # Yes, would else prefer OIO, Moose and the like
    my $class = ref $_[0] ? ref shift : shift;
    my %args = @_; 
    my %members = map { exists($args{$_}) ? $_ => delete $args{$_} : () } qw(
        id line title priority description steps
    );
    croak "Invalid arguments: ", join(", ", keys %args), "!\n" if %args;
    my @desc = parse_description($args{description});
    if (@desc == 1 and my $d = $desc[0]) {
       $args{description} = $d->{description};
       $args{steps} = $d->{substeps};
    }
    bless \%args, $class;
}

sub parse_description {
    # description { 1/1 substep_A | 3 substep_B { ... } | ! 2 substep }
    use Text::Balanced qw(extract_bracketed);
    my $text = shift;
    my ($description,$substeps);

    my @desc;
    while (
      ($substeps, $text, $description)
        = extract_bracketed($text,"{}")
    ) {
       $text =~ s{ \A \s* \| \s* }{}xms;
       my @substeps = parse_description($substeps);
       my $progress =
           $description =~ s{ \A (?:(\d+)\/)? (\d+) \s* }{}xms ? [$1,$2]
         : $description =~ s{ \A (\# \s*)? }{}xms              ? [$1?1:0,1]
         : die # should never happen
         ; 
                    ; 
       push @desc, {
           progress => $progress,
           description => $description,
           substeps => \@substeps,
       };
    }

    return @desc;
}



