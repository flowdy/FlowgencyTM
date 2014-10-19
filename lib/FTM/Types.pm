
package FTM::Types;
use Moose::Util::TypeConstraints;
use FTM::Time::Point;

coerce 'FTM::Time::Point',
    from 'Str'      => via { FTM::Time::Point->parse_ts(shift) },
    from 'Num'      => via { FTM::Time::Point->from_epoch(shift, 3, 3) },
    from 'ArrayRef' => via { FTM::Time::Point->from(@$_) }
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


