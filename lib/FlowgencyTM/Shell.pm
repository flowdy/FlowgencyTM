use strict;
use 5.014;

package FlowgencyTM::Shell; 
use File::Temp qw(tempdir);
use Carp qw(croak carp);
use Getopt::Long qw(GetOptionsFromArray);
use FlowgencyTM;
use Try::Tiny;
use Cwd qw(abs_path);

use base 'Exporter';
our @EXPORT = qw(xec); 
sub xec { # so call: perl [-I...] -MFlowgencyTM::Shell -exec $func_or_shell [ARGS]
          #   -or-   perl .../FlowTime/Shell.pm $func_or_shell [ARGS]  
    no strict 'refs';
    my ($func,@args) = @ARGV;
    exit &$func(@args);
}

# Registering our commands ...
my %CMD = do { 
    use Module::Find;
    my @return;
    for my $cmd ( usesub __PACKAGE__.'::Command' ) {
        my ($short) = $cmd =~ m{ (\w+) \z }xms
            or die "Regex does not match $cmd";
        push @return, $short => $cmd;
    }
    @return;
};


my @EXTERNALS_TO_PROVIDE = (
    map( { $ENV{$_} // () } qw(EDITOR PAGER) ),
    qw(ls nano vim emacs)
);

# Following hash definitions relate to the scripts the shell will process to
# initialize itself. These scripts are stored in this file below the __DATA__
# marker. Look out for '##WHATEVER##' substrings which are substituted by the
# value of the enclosed key, i.e. stringified by _define_vars callback to a
# list of variable definitions.
my %STD_CONFIG = ( # Shell initialization
   # relied on by _prepare_rcfile()
   'EXITALIAS' => join(" ", qw(q quit bye)),
   'EXTERNALS' => join(" ", @EXTERNALS_TO_PROVIDE),
   'COMMANDS'  => join(" ", keys %CMD),
);

my %SUPPORTED_SHELLS = (
   # Add new supported shells here.
   # make sure appropriate config sections (see __DATA__ postamble below)
   # have them registered after the introductory #CONFIG line
   map { $_ => \%STD_CONFIG } qw(bash)
);

for my $shell ( keys %SUPPORTED_SHELLS ) {
    no strict 'refs';
    *{$shell} = sub { shell($shell, @_) };
}

my %special_imports = (
   # define module initialization code here
   # command => \%keyvalue_pairs_for_command_constructor,
); 

sub _init_commands () {
    while ( my ($short, $class) = each %CMD ) {
        my $imports = delete $special_imports{$short};
        my $command = $class->new( $imports ? %$imports : () );
        $CMD{$short} = sub { $command->run(@_); } # returns code-ref
            // die "$command does not provide a run() subroutine\n";
    }
    if ( %special_imports ) {
        die "The following commands could not be found: ".
            join ", ", keys %special_imports;
    }
}

my $interaction_stage;
sub listen_to_fifo {
    my ($fifo_in, $retval_store) = @_;
    $retval_store = (-w $retval_store//'') ? $retval_store : '/dev/null';

    print welcome();

    open my $RETURN2SH, '>', $retval_store or die "Could not open $retval_store: $!";

    _init_commands;

    # Just ensure the database is deployed and ready.
    FlowgencyTM::database; 

    print "DONE.\nNow ensuring the database contains a user entity ... ";
    
    # We will use a code-ref for our part in the foreground ping-pong.
    # We call it first right after assignment to get a current user:
    $_->( run_command( user => getpwuid($<) ) )
        for my $return_to_shell = sub {

        my ($retval) = @_ ? pop : 1;

        # Pass, via fifo, ...
        say {$RETURN2SH} join " ",
          # 0 = success or 1-255 = error as is shell convention:
            $retval eq '1' ? 0 : !$retval ? 1 : $retval,
          # the context string for the shell prompt:
            FlowgencyTM::Shell::Command::context_info() || "NO_CONTEXT"
            ;

        # Now, let's pass foreground control back to the shell that
        # that should just `bg`, i.e. CONTinue us again:
        kill STOP => $$; # - so we do not have to press \cC.

    };
    
    $interaction_stage = 1;

    while ( -p $fifo_in ) {

        open my $cmd_source, '<', $fifo_in
            or die "Could not open fifo $fifo_in: $!";
    
        my $input_sep = <$cmd_source>; # blocking until a command arrives

        $input_sep =~ s{ \A FlowgencyTM\/INPUT_SEPARATOR \s* \W \s* (?=\d{5}) }{}xms
            or die "Could not recognize preamble containing the input ",
                   "separator: $input_sep"
            ;
    
        local $/ = "\n$input_sep"; 
        if ( chomp(my @parts = <$cmd_source>) ) {
            1 until -t *STDIN; # (maybe) wait for foreground
            $return_to_shell->( run_command(@parts) );
        }
        close $cmd_source;
    }
    
    print "FIFO $fifo_in lost. End of while loop reached!\n";
    close $RETURN2SH;

}

sub run_command {
    my ($command, @arguments) = @_;
    my $sub = $CMD{$command} // die "No Command $command supported\n";
    my $retval = $interaction_stage
        ? try { $DB::single = 1; $sub->(@arguments); }
          catch { warn "Sorry, an ERROR occurred:\n\t", shift, "\n"; 255; }
        : $sub->(@arguments)
        ;
    return $retval;
}

sub shell {

    print "Configuring sub-shell ...\n";
    my $shell = @_ && $_[0] !~ /^-/ ? shift : undef;
    if ( !defined $shell ) {
        my @STD_SHELL = (split qr{/}, $ENV{SHELL})[-1] || ();
        for my $sh ( @STD_SHELL, keys %SUPPORTED_SHELLS ) { 
            next if !qx(which $sh); # ^ TODO: use list to reflect order
            $shell = $sh;
            last;
        }
        croak "No supported shell found.\n" if !$shell;
    } 
    
    # Load replacements for all the ##WHATEVER## substrings in the config
    my %config_inserts = %{
        $SUPPORTED_SHELLS{$shell}
            // croak "This shell is not supported: $shell"
    };

    # Complete the variables
    my $tempdir = tempdir();
    GetOptionsFromArray( \@_, 'database|d=s' => \my $database);
    $ENV{TMPDIR} = $tempdir;
    if ( $database ) {
        $ENV{FLOWDB_SQLITE_FILE} = abs_path($database);
    }

    # Extract from __DATA__ postamble the relevant sections introduced
    # each by a line #CONFIG ... $shell ...
    my $rc = _prepare_rcfile(\%config_inserts => $shell);
    my $rcfile = "$tempdir/shellrc";
    if ( open my $fh, '>', $rcfile ) {
        print $fh $rc;
        close $fh;
    }
    else { croak "Could not open $rcfile to write to: $!" }   
    
    print "Now exec()'ing $shell with the compiled rcfile instead of the "
        . "default one ...\n";
    exec $shell, '--rcfile', $rcfile
        or print STDERR "Could not exec() $shell: $!";

}

sub _prepare_rcfile {
    my ($inserts, $shell) = @_;
    my $define_vars = delete $inserts->{_define_vars};
    my $rc = qq{echo \$SHELL starting on behalf of }.__PACKAGE__.qq{ ...\n};

    while ( $_ = <DATA> ) {
        $rc .= $_ if (/^#CONFIG\b/ && /\b$shell\b/) .. /^#END/;
    }
    close DATA;

    $rc =~ s{ (?<!\#)\#\#(\w+)\#\#(?!\#) }
            { my $lines = delete $inserts->{$1};
              croak "No hooks for $1 (or used once more)" if !$lines;
              croak "string is a reference" if ref $lines;
              $lines
            }egxms;

    return $rc;

}

sub _std_define_shellvars {
    my ($array, $export) = @_;
    my @array = @$array;
    my @return;
    $export = $export ? 'export ' : '';
    while ( my ($var, $value) = splice @array, 0, 2 ) {
        push @return, sprintf $export.q{%s="%s"}, $var => $value;
    }
    join "\n", @return;
}


sub welcome { chomp( my $msg = <<'WELCOME' ); $msg }

  /=======================================================================\
  #   FlowgencyTM Shell :: Manage your tasks, your time - and your flow   #
  # --------------------------------------------------------------------- #
  #                                                                       #
  # This is a DEVELOPERS' command-line interface of the task and time     #
  # management tool FlowgencyTM. A web-browser driven GUI and mobile app  #
  # is planned but it follows the implementation and the debugging of the #
  # core logic of the software in my priority list.                       #
  #                                                                       #
  # WARNING: This shell is not for productive use! Play with FlowgencyTM  #
  # and find out what takes our automatic test suite further to comple-   #
  # tion: This is the intended purpose of this shell.                     #
  #                                                                       #
  \=======================================================================/
  
  (C) 2012-2014 Florian Heß
  
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
  

Initializing FlowTime::Shell ...
WELCOME

1;

__DATA__

#CONFIG bash

PS1="FTM:PROMPT_LEFT_UNSET>"
# Initialize FlowgencyTM::Shell commands
for i in ##COMMANDS##; do
    alias $i="__delegate_to_flowtimeter_shell $i"
done

for i in ##EXITALIAS##; do
    alias $i=exit
done

# Initialize needed binaries
for i in ##EXTERNALS##; do
    i=$(which $i)
    [ "$i" ] || continue
    alias $(basename $i)=$i
done

PERL_BIN=$(which perl)

unset HISTFILE

# FlowgencyTM::Shell and $SHELL communicate by FIFO:
FINFO=$TMPDIR/command.fifo   ; mkfifo $FINFO
RETVL=$TMPDIR/shretval       ; > $RETVL # normal file ( tried fifo as well - dead lock )     

PROMPT_COMMAND=__init_interaction # will just be reset at the end of this function:
__init_interaction () {
    local FLOWTIMETER_SHELL_PROCESS="/usr/bin/perl -MFlowgencyTM::Shell -${DEBUG2:+d}exec listen_to_fifo $FINFO $RETVL"
    $FLOWTIMETER_SHELL_PROCESS
    # when perl has sent itself the stop signal, continue it in the background
    [ "$(jobs -s)" ] && bg || { # ... or abort and exit with an error message
        echo FlowgencyTM::Shell could not initialize properly
        exit 1
    } 
    echo
    echo "FlowgencyTM is initialized and now made continue waiting for input in the background."
    echo "Next comes the prompt of your shell that is no ready to serve it" \
         "all commands implemented in a FlowgencyTM::Shell::Command::* module each."
    echo
    echo "Hints concerning configuration of your shell:"
    echo " * Your HOME path is" $HOME
    echo "   It is temporary and will be deleted when the shell terminates."
    echo " * PATH environment variable has been emptied, so you"
    echo "   won't be able to execute any external commands or programs unless"
    echo "   you address them with their path."
    echo "   Run 'alias' to see all commands that have been aliased in order to work"
    echo "   notwithstanding."
    echo
    unset PROMPT_COMMAND
    __update_prompt
}

__update_prompt () {
    read EXITCODE PROMPTINFO < $RETVL 
    PS1="FTM:\[\e[1;32m\]$PROMPTINFO:\w\[\e[0m\]> " 
    return $EXITCODE
}

__delegate_to_flowtimeter_shell () {
    local separator=$RANDOM$RANDOM$RANDOM$RANDOM$RANDOM
    { echo FlowgencyTM/INPUT_SEPARATOR = $separator
      for i in "$@"; do
          printf "%s\n" "$i"
          printf "%s\n" $separator
      done
    } > $FINFO
    { fg %1; bg; } > /dev/null
    __update_prompt
    if [ -z "$(jobs -r)" ]; then exit; fi
}

__cleanup () {
    /bin/rm -r $TMPDIR
    local leftover=$(jobs -rsp)
    [ "$leftover" ] && kill $leftover
    echo Cleaned up.
}
trap __cleanup EXIT

HOME=$TMPDIR; cd
PATH=

#END
