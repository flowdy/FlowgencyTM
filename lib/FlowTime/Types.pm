
package FlowTime::Types;
use Moose::Util::TypeConstraints;
use Time::Point;

coerce 'Time::Point'
    => from 'Str'
    => via { Time::Point->parse_ts(shift) };

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


