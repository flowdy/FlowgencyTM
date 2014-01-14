use strict;

package User;
use Moose;
use Time::Model;
use User::Tasks;
use JSON;

has _dbicrow => (
    is => 'ro',
    isa => 'FlowDB::User',
    required => 1,
    handles => [qw/ id username /],
    init_arg => "dbicrow",
);

has _time_model => (
    is => 'ro',
    isa => 'Time::Model',
    lazy => 1,
    init_arg => undef,
    default => sub {
        my ($self) = shift;
        Time::Model->from_json(shift->_dbicrow->time_model);    
    }
};

has tasks => (
    is => 'ro',
    isa => 'User::Tasks',
    init_args => undef,
    default => sub {
        my $self = shift;
        User::Tasks->new(
            time_profile_provider => sub {
                $self->_time_model->get(shift);
            }, 
            flowrank_processor => $self->flowrank_processor,
            tasks_rs => $self->_dbicrow->tasks,
        );
    },
    lazy => 1,
};

has weights => (
    is => 'ro',
    isa => 'HashRef[Int]',
    default => sub {
        return from_json(shift->_dbicrow->weights);
    },
};
    
sub time_model {
    my ($self, $json) = @_;
    my $model = $self->_time_model;
    if ( defined $json ) {
        $model->update_from_json($json);
        $self->_dbicrow->update({ time_model => $json });
    }
    return $model;
}

sub flowrank_processor {
    my $self = shift;

    my (@hrefs,%minmax,%wgh);
    
    $_->() for my $reset = sub {
        %wgh = %{ $self->weights };
        $minmax{$_} = [0,0] for keys %wgh;
        @hrefs = ();
    };

    return sub {

        my $href = shift;
        
        if ( $href eq "rank" ) {

            $_->[1] -= $_->[0] for values %minmax;

            for my $href ( @hrefs ) {

                my ($rank,$wgh);
                while ( my ($which, $value) = each %$href ) {
                    $wgh    = $wgh{$which} // next;
                    $value -= $minmax{$which}[0];
                    $rank  += abs($wgh) * abs(
                        $value / $minmax{$which}[1] - ($wgh < 0)
                    );
                }

                $href->{"FlowRank"} = $rank;

            }

            $reset->();
            return;
        }
        elsif ( ref $href eq "HASH" ) {
            while ( my ($which, $value) = each %$href ) {
                $value < $_ and $_ = $value for $minmax{$which}[0];
                $value > $_ and $_ = $value for $minmax{$which}[1];
            }
            return $href;
        }        
        else {
            croak "expecting a plain Hash reference";
        }
        
    };
}
__PACKAGE->meta->make_immutable;
