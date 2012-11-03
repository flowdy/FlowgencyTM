CREATE TABLE `preqs` (
    `any_task_step` integer8 not null references `steps` on delete cascade,
    `required_for` char(15) not null references `tasks` on delete cascade,
    `only_steps` tinytext,
    `weight` int1,
    `description` mediumtext
);

CREATE TABLE `step4step` (
    `prior` integer8 not null references `steps` on delete cascade,
    `before` integer8 not null references `steps` on delete cascade
);

CREATE TABLE `steps` (
    `task` char(15) not null references `tasks` on delete cascade,
    `ID` char(8) not null,
    `parent` integer8 references `steps`,
    `title` varchar(255) not null,
    `description` mediumtext,
    `weight` tinyint,
    `seq_nr` tinyint,
    `done` tinyint,
    `restrict_on` tinytext
);

CREATE TABLE `tasks` (
    `ID` char(15) not null primary key,
    -- `title` varchar(255) not null,
    `entrydate` datetime not null default current_timestamp,
    `ultimatum` datetime not null,
    `defstep` integer8 not null references `steps` on delete cascade,
    `priority` tinyint,
    -- `description` mediumtext
);

CREATE UNIQUE INDEX `tasksteps` on `steps` (`task`,`ID`);
CREATE UNIQUE INDEX `taskdefstep` on `tasks` (`defstep`);

