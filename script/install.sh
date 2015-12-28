#!/bin/bash
# Run this install script before you run script/daemon the first time!

export FLOWDB_SQLITE_FILE="${1:-flow.db}"

echo -n "Initializing database file $FLOWDB_SQLITE_FILE ... "
sqlite_cmd=$(which sqlite3)
if [ -z "$sqlite_cmd" ]; then
    echo 'FAILED: Cannot find and execute `sqlite3` command!' 1>&2
    exit 1
fi

if [ -e "$FLOWDB_SQLITE_FILE" ]; then
    echo 'FAILED: File exists.' 1>&2
    exit 1
fi

current_schema=$(ls -r schema/version_* | head -1)
$sqlite_cmd $FLOWDB_SQLITE_FILE < $current_schema && echo OK. && \
    ln -s "$(basename $current_schema)" schema/used_version

USER=$(whoami)
cat <<'END_OF_INFO'
Now, please define the standard rhythm of default time track.
Otherwise, if you just hit ENTER, FlowgencyTM expects in urgency calculations that you work non-stop 24/7. There will soon be a convenient time model configuration in the user settings. The "How to get started" screen that already appears to a new user will recommend it as the initial step. But it is being developped, yet. What you see is a prototype only. It waits for JSON input and is not quite intended for wider use. Hence, for the time being you should define it rather now.

Please follow the syntax outlined by the examples below: 
  * Mo-Fr@9-16
    --> Traditional work day pattern, "Nine to five"
     !  Note: Omitted minute part in "until" times implies HH:59
  * Mo-Fr@9-16,!12
    --> same with a lunch break from 12 to 12:59
  * Mo-Tu,Th-Sa@...
    --> Separate also the week days with comma if needed
     !  Note: Mo-Fr,!We@... wouldn't get parsed, exclusion is supported for the hours only.
  * Mo-We@9-12,Th-Sa@15-18,Sa@14,!18
    --> different patterns for the halfs of a week, the specifications for Saturday will get merged.
     !  Note: When indicating minutes prefer common parts like halfs, thirds or
        quaters of the hour to save hardware resources. The less equal parts an hour
        needs to be resolved into, the more efficiently the pattern can be stored
        and processed.
  * 2n:Mo-Tu@9-16,We@9-12;2n+1:We@12-16,Th-Fr@9-16
    --> different patterns for alternate weeks (based on ISO week number)

END_OF_INFO

read -e -p '? Default rhythm of time model: ' -i 'Mo-Su@0-23' TIME_MODEL
echo 'Now, issue `script/daemon start`, then open the URL shown in your webbrowser.'
perl -Ilib -MFlowgencyTM <<END_OF_PERL && echo 'Default time track changed here, therefore you can skip step #1 explained in the Get Started screen.' 
my \$user = FlowgencyTM::user('$USER',1);
\$user->insert;
if ( length '$TIME_MODEL' && '$TIME_MODEL' ne 'Mo-Su@0-23' ) {
    \$user->update_time_model({
       default => { label => 'May mindful work clean breaks from worry', week_pattern => '$TIME_MODEL' }
    });
}
else { exit 1; }
END_OF_PERL

cat > local.rc <<END_OF_CONFIG
FLOWGENCYTM_USER=$USER
FLOWDB_SQLITE_FILE=$FLOWDB_SQLITE_FILE
FLOWGENCYTM_ADMIN=\$FLOWGENCYTM_USER # to activate new accounts
MAX_USERS_IN_CACHE=5                 # if multi-user web access permitted
MOJO_LISTEN=http://127.0.0.1:3000
PIDFILE=/var/lock/flowgencytm.pid
LOG=server.log
COMMAND=morbo    # or 'server daemon', 'server prefork'
END_OF_CONFIG

