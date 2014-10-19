use strict;

package FlowTiMeter::Shell::Command::timetracks;
use base 'FlowTiMeter::Shell::Command';
use Getopt::Long qw(GetOptionsFromArray);
use Encode qw(decode_utf8);

my @OPTIONS = qw[
    label|l=s
    successor|s=s
    unmentioned_variations_from|unmentioned-variations-from|p=s@
    default_inherit_mode|default-inherit-mode|I=s
    force_receive_mode|force-receive-mode|f|R=s
    from_earliest|from-earliest|earliest=s
    until_latest|until-latest|latest=s
];

my @SPAN_OPTIONS = qw[
    week_pattern|week-pattern|w=s
    week_pattern_from_track|week-pattern-from-track|wp-from=s
    from_date|from-date=s
    until_date|until-date|=s
    ref|r=s
    section_from_track|section-from-track=s
];

my ($tmp_variation_href, $base_variation);
sub handle_variations {
    my ($opt,$value) = @_;
    if ($tmp_variation_href) {
        $tmp_variation_href->{$opt} = $value;
    }
    else {
        die "$opt not supported in timetrack definition"
            if $opt ne 'week_pattern'
            && $opt ne 'ref'
            ;
        $base_variation->{$opt} = $value
    }
}

sub run {
    my $self = shift;
    my %to_update;
    my $current_track = [];
    my @track_data = ($current_track);

    while ( my $arg = shift ) {
        if ( $arg eq '-T' || $arg eq '--track' ) {
            push @track_data, $current_track = [];
            next;
        }
        else { push @$current_track, $arg; }
    }

    for my $def ( @track_data ) {
        my $name = $_[0] !~ /^-/
            ? shift @$def
            : die "Track name required";
        my @variations;
        my %params = (
            'reset!' => \my $reset,
            'variation|v=s' => sub {
                push @variations, $tmp_variation_href = { name => pop };
            }
        );
        for my $opt (@SPAN_OPTIONS) {
            $params{$opt} = \&handle_variations;
        }         
        my $properties = {};
        GetOptionsFromArray($def => $properties, %params, @OPTIONS);
        unshift @variations, undef if !$reset;
        $properties->{variations} = \@variations;
        $properties->{week_pattern} = $base_variation->{week_pattern};
        $_ = decode_utf8($_) for $properties->{label} // ();
        $to_update{$name} = $properties;
    }
    continue {
        ($base_variation, $tmp_variation_href) = ();
    }

    FlowTiMeter::user->update_time_model(\%to_update);

    return 1;
}

1;
