
package FTM::Types;
use Moose::Util::TypeConstraints;
use FTM::Time::Spec;
use FTM::Time::Rhythm;
use Date::Calc qw(Today);

coerce 'FTM::Time::Spec',
    from 'Str'      => via { FTM::Time::Spec->parse_ts(shift) },
    from 'Num'      => via { FTM::Time::Spec->from_epoch(shift, 3, 3) },
    from 'ArrayRef' => via { FTM::Time::Spec->from(@$_) }
    ;

subtype 'RgbColour',
    as 'ArrayRef',
    where { @$_ == 3 && @$_ == (() = grep {
        $_ eq abs(int($_)) && $_ >= 0 && $_ < 256
      } @$_)
    },
    message { 'expecting array ref of three 8-bit positive ints '
            . 'for red, green, blue colour components'
    };
;

coerce 'RgbColour',
    from 'Str',
    via {[ map { hex($_) } m{ \A \# (?: ([0-9a-f][0-9a-f]) ){3} \z }xms ]}
    ;

coerce 'FTM::Time::Rhythm'
    from 'Str',
    via { FTM::Time::Rhythm->from_string( shift, { init_day => [ Today() ] }) }
    ;
