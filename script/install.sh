#!/bin/bash
# Run this install script before you run script/daemon the first time!

export FLOWDB_SQLITE_FILE="${1:-flow.db}"

sqlite3 $FLOWDB_SQLITE_FILE <<'END_OF_SQL'
CREATE TABLE task (
  task_id INTEGER PRIMARY KEY NOT NULL,
  user_id ,
  name ,
  title  NOT NULL,
  main_step_id ,
  from_date  NOT NULL,
  priority INTEGER NOT NULL,
  open_since INTEGER,
  archived_because ,
  archived_ts ,
  repeat_from ,
  repeat_until ,
  frequency ,
  client ,
  FOREIGN KEY (main_step_id) REFERENCES step(step_id),
  FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE TABLE timesegment (
  task_id  NOT NULL,
  until_date  NOT NULL,
  track  NOT NULL,
  lock_opt ,
  FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX task_idx_main_step_id ON task (main_step_id);
CREATE INDEX task_idx_user_id ON task (user_id);
CREATE INDEX timesegment_idx_task_id ON timesegment (task_id);
CREATE UNIQUE INDEX user_task ON task (user_id, name);
CREATE UNIQUE INDEX task_mainstep ON task (main_step_id);
CREATE TABLE step (
  step_id INTEGER PRIMARY KEY NOT NULL,
  checks INTEGER NOT NULL DEFAULT 1,
  done INTEGER NOT NULL DEFAULT 0,
  description ,
  expoftime_share INTEGER NOT NULL DEFAULT 1,
  name  NOT NULL DEFAULT '',
  link_id INTEGER,
  parent_id INTEGER,
  pos FLOAT,
  task_id INTEGER NOT NULL,
  FOREIGN KEY (link_id) REFERENCES step(step_id) ON DELETE CASCADE,
  FOREIGN KEY (parent_id) REFERENCES step(step_id) ON DELETE CASCADE,
  FOREIGN KEY (task_id) REFERENCES task(task_id) ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX step_idx_link_id ON step (link_id);
CREATE INDEX step_idx_parent_id ON step (parent_id);
CREATE INDEX step_idx_task_id ON step (task_id);
CREATE UNIQUE INDEX tree ON step (task_id, name);
CREATE INDEX links ON step (link_id);
CREATE TABLE "user" (
  user_id  NOT NULL,
  password  NOT NULL,
  weights  NOT NULL,
  time_model  NOT NULL,
  priorities  NOT NULL,
  appendix FLOAT NOT NULL DEFAULT 0.1,
  username ,
  email ,
  created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id)
);
CREATE TABLE mailoop (
  user_id  NOT NULL,
  type  NOT NULL,
  token  NOT NULL,
  value ,
  request_date DATETIME,
  PRIMARY KEY (user_id),
  FOREIGN KEY (user_id) REFERENCES user(user_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX token ON mailoop (token);
END_OF_SQL

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
  * Mo-Di,Do-Sa@...
    --> Separate also the week days with comma if needed
     !  Note: Mo-Fr,!We@... wouldn't get parsed, exclusion is supported for the hours only.
  * Mo-We@9-12,Do-Sa@15-18,Sa@14,!18
    --> different patterns for the halfs of a week, the specifications for Saturday will get merged.
     !  Note: When indicating minutes prefer common parts like halfs, thirds or
        quaters of the hour to save hardware resources (the less parts an hour
        needs to be split into, the better is memory usage and performance).

END_OF_INFO

read -e -p '? Default rhythm of time model: ' -i 'Mo-So@0-23' TIME_MODEL
perl -Ilib -MFlowgencyTM <<END_OF_PERL && echo 'Default time track changed. Now you can skip the first step listed in the Get Started screen.'
my \$user = FlowgencyTM::user('$USER',1);
\$user->insert;
if ( length '$TIME_MODEL' && '$TIME_MODEL' ne 'Mo-So@0-23' ) {
    \$user->update_time_model({
       default => { label => 'May mindful work clean breaks from worry', week_pattern => '$TIME_MODEL' }
    });
}
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

