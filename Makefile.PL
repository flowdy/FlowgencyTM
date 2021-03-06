use utf8;
use ExtUtils::MakeMaker;

WriteMakefile(
    AUTHOR            => "Florian Heß",
    NAME              => "FlowgencyTM",
    ABSTRACT          => 'The task & time manager for a more humanely multitasking business',
    VERSION_FROM      => "lib/FlowgencyTM.pm",
    PREREQ_PM         => {
        'Algorithm::Dependency' => 0, # OK, 1.110
        'Benchmark' => 0, # OK, 1.15
        'Bit::Vector' => 0, # OK, 7.3
        'Carp' => 0, # OK, 1.29
        'Date::Calc' => 0, # OK, 6.3
        'DBIx::Class' => 0, # OK, 0.08
        'FindBin' => 0, # OK, 1.51
        'JSON' => 0, # OK, 2.61
        'Mojolicious' => 6, # OK
        'Moose' => 0, # OK, 2.1210
        'POSIX' => 0, # OK, 1.32
        'Scalar::Util' => 0, # OK, 1.27
        'Test::More' => 0, # OK, 0.98
        'Throwable'  => 0, # OK, 0.200012
        'Time::Local' => 0, # OK, 1.2300
        'Test::Exception' => 0, # OK, 0.32
    }
);
