<!-- [% META pagetitle = "Installation Guide" %] -->

Installation Guide
==================

FlowgencyTM is beta. This means that crashes, corrupted or inconsistent data or other unconveniences cannot be excluded. So do not use it for vital projects yet. If you really cannot help doing, backup often! Please file bug-reports to flowgencytm-dev at <span>mailbox.</span>org, for which I thank you very much in advance.

FlowgencyTM is implemented in the Perl programming language, version 5.14+. Mac OS X and most linux distributions include it ready for use. Ensure it is installed by running the command `perl -v`, or search the web how to install the latest version on your system. Windows users are recommended Strawberry Perl, please download from <http://strawberryperl.com/>.

Clone the git repository in a directory of your choice. With plain git on Linux enter at a shell prompt:

    $ git clone https://github.com/flowdy/FlowgencyTM.git
    $ cd FlowgencyTM/
    $ perl Makefile.PL

For other systems, install the Git DVCS and do the according steps (cf. manual). All commands below are tested on a Debian 8 (stable) system. With another system, you may have to vary them.

Check the dependencies
----------------------

Check and install any prerequisites by running inside the FlowgencyTM directory, provided cpanm tool is installed on your system:

    cpanm --installdeps .

Instead, you might prefer installing the packages that your linux distribution repository provides. E.g. if you want to install FlowgencyTM on your Raspbian-driven Pi (which however I do not quite recommend because it is rather slow):

    $ git clone https://github.com/flowdy/FlowgencyTM.git
    $ cd FlowgencyTM/
    $ script/gather_check_dependencies 
      # analyze output for missing modules ...
    $ sudo apt-get install libmoose-perl libdate-calc-perl libjson-perl \
      libtest-exception-perl libalgorithm-dependency-perl libdbix-class-perl \
      libthrowable-perl libdbd-sqlite3-perl libtext-markdown-perl \
      sqlite3 cpanminus
    $ sudo cpanm Mojolicious # newer version, that one in the repo is deprecated
    $ prove -rl t                      

Bootstrap `flow.db` database file
---------------------------------

FlowgencyTM does not yet work right from the box in a webbrowser. First, you need to initialize it, i.e. create a database, a user and also modify the time model unless you want to work 24/7:

    $ script/install.sh

This script also writes local.rc file used for script/daemon.

Start and manage the server
---------------------------

    $ script/daemon start
      # waits for the first log line printed to file, then exits
      # server process in the background runs until 'stop' command
    $ script/daemon status # whenever you want
      # status info and most recent log lines
    $ script/daemon restart|update|stop # 'update' = 'restart'
                                        # with `git pull` in between


