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

1 of 2) DEFAULT TIME TRACK
=========================================================================

Please define the standard rhythm of default time track. Otherwise,
if you just hit ENTER, FlowgencyTM expects in urgency calculations that
you work non-stop 24/7. The "Get Started" screen that appears if the user
has no tasks yet, will provide a link to a settings form which also
includes the time model configuration so you can change it easily.

Please follow the syntax outlined in the examples below:
--------------------------------------------------------
 
  * Mo-Fr@9-16
    --> Traditional work day pattern, "Nine to five"
     !  Note: Omitted minute part in "until" times implies HH:59

  * Mo-Fr@9-16,!12
    --> same with a lunch break from 12 to 12:59

  * Mo-Tu,Th-Sa@...
    --> Separate also the week days with comma if needed
     !  Note: Mo-Fr,!We@... wouldn't get parsed, exclusion is supported
        for the hours only.

  * Mo-We@9-12,Th-Sa@15-18,Sa@14,!18
    --> different patterns for the halfs of a week, the specifications
        for Saturday will get merged.
     !  Note: When indicating minutes prefer common parts like halfs,
        thirds or quaters of the hour to save hardware resources. The less
        equal parts an hour needs to be resolved into, the more
        efficiently the pattern can be stored, and the faster it is
        processed, too.

  * 2n:Mo-Tu@9-16,We@9-12;2n+1:We@12-16,Th-Fr@9-16
    --> different patterns for alternate weeks (based on ISO week number)

END_OF_INFO

read -e -p '? Default rhythm of time model: ' -i 'Mo-Su@0-23' TIME_MODEL

cat <<"EOF"


2 of 2) PASSWORD
========================================================================

If you want to share the service with other users – beware, you are on
your own to care for enough reliability and their privacy! – you need a
password securing your admin account. Please set it at the prompt below
(password is not printed on screen while typing).

Do you want to make the service accessible from other devices? Then please
adjust (later) MOJO_LISTEN in local.rc file to something different from
IP 127.0.0.1 or localhost, according to your local network configuration. 

Otherwise, just press enter so you are auto-logged in, given you use the
same device as the server is running on.

EOF

TMPDIR=$(mktemp -d)

NO="#"
YES=
while true; do
    read -rs -e -p "? Password for admin account ($USER): " PASSWORD
    if [ "$PASSWORD" == "" ]; then
       IS_ADMIN=$NO
       AUTOLOGIN=$YES
       break
    else
       IS_ADMIN=$YES
       AUTOLOGIN=$NO
       echo
    fi
    read -rs -e -p "? Please confirm password by re-entering: " PASSWORD2
    [ "$PASSWORD" == "$PASSWORD2" ] && break
    echo
done

echo
echo $PASSWORD > $TMPDIR/pw

perl -Ilib -MFlowgencyTM <<END_OF_PERL

my \$user = FlowgencyTM::user('$USER',1);
\$0="FlowgencyTM setup script";
\$user->insert;
if ( length '$TIME_MODEL' && '$TIME_MODEL' ne 'Mo-Su@0-23' ) {
    \$user->update_time_model({
       default => { label => 'May mindful work clean breaks from worry', week_pattern => '$TIME_MODEL' }
    });
}
chomp(my \$pw = do {
    open my \$fh, '<', '$TMPDIR/pw' or die;
    unlink '$TMPDIR/pw';
    local \$/ = undef;
    <\$fh>;
});
if ( length \$pw ) {
   \$user->salted_password(\$pw);
   \$user->update();
}
else {
   warn "Password has no length.\n"
}
END_OF_PERL

cat > local.rc <<END_OF_CONFIG
${AUTOLOGIN}FLOWGENCYTM_USER=$USER
FLOWDB_SQLITE_FILE=$FLOWDB_SQLITE_FILE
${IS_ADMIN}FLOWGENCYTM_ADMIN=$USER # to activate new accounts
MAX_USERS_IN_CACHE=5                  # ... if multi-user web access permitted
MOJO_LISTEN=http://127.0.0.1:3000
PIDFILE=/var/lock/flowgencytm.pid
LOG=server.log
COMMAND=morbo    # or 'server daemon', 'server prefork'
END_OF_CONFIG

echo
echo 'Now, please issue `script/daemon start`, then load the URL that is shown.'

