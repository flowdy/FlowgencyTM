#!/usr/bin/perl
use strict;

package FlowgencyTM::Test::Environment;
use Test::More;

# used to eval herein later on by EvalPerl sub parser

package FlowgencyTM::Script::Processor;
use FlowgencyTM::Script::Parser;
use Moose;
use Carp qw(croak);

has path => ( is => 'ro', isa => 'Str', required => 1 );

has ['_block_cnt', '_filepos'] => (
    is => 'rw',
    isa => 'Int',
    init_arg => undef,
    default => 0,
);

has parser_farm => (
    is => 'ro',
    isa => 'HashRef',
    default => sub { {} },
);

has current_user => (
    is => 'ro', # to be changed by reference
    isa => 'FTM::User',
);
sub _current_user_ref {
    my ($self) = @_;
    return \$self->{current_user};
}

require FTM::Time::Spec;
has now => (
    is => 'rw',
    isa => 'FTM::Time::Spec',
);

my %SUPPORTED_DIRECTIVES = (
    USER => {
       handler => 'SwitchUser',
       init => sub {
           my ($parser) = @_;
           return 
               user_source => sub { FlowgencyTM::get_user(shift) },
               user_ref    => $parser->_current_user_ref
           ;
       },
    },
    NOW => {
       handler => 'ResetTime',
       init => sub {
           my ($parser) = @_;
           time_setter => sub {
               my $now = $parser->now;
               $parser->now(FTM::Time::Spec->parse_ts(
                   shift, $now && $now->date_components
               ));
           },
       }
    },
    TEST => {
       handler => 'EvalPerl',
       init => sub { environment => 'FlowgencyTM::Test::Environment' },
    },
    TIMES => {
       handler => 'ManageTimeProfiles',
       init => sub {
           my ($parser) = @_;
           manager => sub {
              my ($func, @args) = @_;
              my $model = $parser->current_user->time_model;
              my @ret = $model->$func(@args);
              $parser->current_user->update(
                  time_model => $model->serialize
              };
           },
       }
    },
    DISPLAY => {
        handler => 'DisplayOnScreen',
        init => sub {
            my ($parser) = @_;
            out_fh => $parser->status_output_filehandle;
        },
    }
);


sub BUILD {
    my ($self) = @_;

    my $farm = $self->parser_farm;
    while ( my ($dir, $init) = each %SUPPORTED_DIRECTIVES ) {
        my $class = "FlowgencyTM::Script::".$init->{handler};
        eval "require $class;" or die $@;
        $init = $init->{init};
        $farm->{$dir} = $class->new( $self->$init() );
    }

}    

1;
