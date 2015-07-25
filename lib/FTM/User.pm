use strict;

package FTM::User;
use Moose;
use Carp qw(croak);
use FTM::Time::Model;
use FTM::User::Tasks;
use FTM::FlowRank;
use JSON qw(from_json to_json);

has _dbicrow => (
    is => 'ro',
    isa => 'FTM::FlowDB::User',
    required => 1,
    handles => [qw/
        user_id username email created salted_password password_equals
        find_related insert invite update in_storage
    /],
    init_arg => "dbicrow",
);

has _time_model => (
    is => 'ro',
    isa => 'FTM::Time::Model',
    lazy => 1,
    init_arg => undef,
    handles => {
        update_time_model => 'update',
        get_available_time_tracks => 'get_available_tracks',
    },
    default => sub {
        my ($self) = shift;
        FTM::Time::Model->from_json($self->_dbicrow->time_model);    
    }
);

has tasks => (
    is => 'ro',
    isa => 'FTM::User::Tasks',
    init_arg => undef,
    builder => '_build_tasks',
    handles => { 'get_task' => 'get', 'search_tasks' => 'search' },
    lazy => 1,
);

has cached_since_date => (
    is => 'ro',
    init_arg => undef,
    default => sub { FTM::Time::Spec->now },
);

has can_admin => (
    is => 'ro',
    isa => 'Bool',
    default => sub { 0 },
);

has can_login => (
    is => 'ro', isa => 'Bool',
    default => sub {
       my $row = shift->_dbicrow;
       $row &&= $row->mailoop or return 1;
       return $row->type ne 'invite';
    }
);

has weights => (
    is => 'ro',
    isa => 'HashRef[Int]',
    auto_deref => 1,
    lazy => 1,
    default => sub {
        return from_json(shift->_dbicrow->weights);
    },
);
    
has _priorities => (
    is => 'ro',
    isa => 'HashRef[Int|Str]',
    auto_deref => 1,
    lazy => 1,
    default => sub {
        my $href = from_json(shift->_dbicrow->priorities);
        my %ret;
        while ( my ($p, $n) = each %$href ) {
            croak "priority $p redefined" if $ret{"p:$n"};
            croak "ambiguous label for priority number $n" if $ret{"n:$p"};
            @ret{ "p:$n", "n:$p" } = ($p, $n);
        }
        return \%ret; 
    },
);

has appendix => (
    is => 'rw',
    isa => 'Num',
    lazy => 1,
    default => sub { shift->_dbicrow->appendix },
    trigger => sub {
        my ($self, $value) = @_;
        $self->_dbicrow->update({ appendix => $value });
    },
);

sub get_labeled_priorities {
    my ($self) = @_;
    my $p = $self->_priorities;
    my $ret = {};
    while ( my ($label, $num) = each %$p ) {
        $label =~ s{^n:}{} or next;
        $ret->{$label} = $num;
    }
    return $ret;
}

sub modify_weights {
    my ($self,%weights) = @_;
    my $w = $self->weights;
    while ( my ($key, $value) = each %weights ) {
        die "Unknown key: $key" if !exists $w->{$key};
        die "Not an integer: $key = $value" if $value !~ /^-?\d+$/;
        $w->{$key} = $value;
    }
    return $self->_dbicrow->update({ weights => to_json($w) });
}

sub remap_priorities {
    my ($self,@priorities) = @_;
    my (%p);
    while ( my ($key, $value) = splice @priorities, 0, 2 ) {
        die "Multiple labels for priority = $value" if exists $p{$value};
        die "Not an integer: $key = $value" if $value !~ /^-?\d+$/;
        $p{$key} = $value;
    }
    delete $self->{_priorities};
    return $self->_dbicrow->update({ priorities => to_json(\%p) });
}

after update_time_model => sub {
    my ($self) = @_;
    $self->_dbicrow->update({
        time_model => $self->_time_model->to_json
    });
};

sub dump_time_model {
    my ($self) = shift;

    my $href = from_json($self->_dbicrow->time_model);

    my $convert_ts = sub {
        my ($href, $from_key, $until_key) = @_;
        my $cnt_defined = 0;
        for ( $href->{ $from_key } // (), $href->{ $until_key } // () ) {
            $_ = FTM::Time::Spec->parse_ts($_);
            $cnt_defined++;
        }
        if ( $cnt_defined == 2 ) {
            $href->{$from_key}->fix_order($href->{$until_key});
        }
    };

    for my $href ( values %$href ) {
        $convert_ts->($href, 'from_earliest', 'until_latest');
        for my $var (@{ $href->{variations} // [] }) {
            $convert_ts->($var, 'from_date', 'until_date');
        } 
    }
    
    return $href;

}    

sub _build_tasks {
    my $self = shift;
    FTM::User::Tasks->new({
        track_finder => sub {
            $self->_time_model->get_track(shift);
        }, 
        flowrank_processor => FTM::FlowRank->new_closure({
            get_weights => sub { $self->weights }
        }),
        priority_resolver => sub {
            $self->_priorities->{ +shift };
        },
        appendix => sub { $self->appendix },
        task_rs => scalar $self->_dbicrow->tasks,
    });
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

FTM::User - Representation of a user, invocator and object of FlowgencyTM actions

=head1 SYNOPSIS

 my $user = FTM::User->new( dbicrow => $row ); # pass a FTM::FlowDB::User row

 my $name = $user->name;
 my %hash = $user->weights;

 $user->update({ name => $new_name });
 $user->tasks->...;
 $user->update_time_model(\%diff_data);
  
=head1 DESCRIPTION

Instances of this class provide proxy closures to be accessed by User::Tasks for
actions involving other entities than tasks.
 
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

