use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => "FlowTime",
    VERSION_FROM      => "lib/FlowTime.pm",
    PREREQ_PM         => {
        'Algorithm::Dependency' => 0, # OK, 1.110
        'Benchmark' => 0, # OK, 1.15
        'Bit::Vector' => 0, # OK, 7.3
        'Carp' => 0, # OK, 1.29
        'Date::Calc' => 0, # OK, 6.3
        'FindBin' => 0, # OK, 1.51
        'JSON' => 0, # OK, 2.61
        'Mojolicious' => 0, # OK, loaded (just version unknown)
        'Moose' => 0, # OK, 2.1210
        'POSIX' => 0, # OK, 1.32
        'Scalar::Util' => 0, # OK, 1.27
        'Test::More' => 0, # OK, 0.98
        'Time::Local' => 0, # OK, 1.2300
        'Test::Exception' => 0, # OK, 0.32
    }
);
