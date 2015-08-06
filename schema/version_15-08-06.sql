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
