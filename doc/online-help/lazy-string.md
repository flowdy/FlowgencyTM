What is this Lazy String syntax?
================================

When you hover the mouse about the new task button, a text box pulls down, offering the opportunity to preset fields of the task form. These presets are defined in a special, write-optimized, read-once syntax. Neither JSON nor YAML nor anything I know is suitable for quickly written almost no-brainers.

Separation
----------

Key/value pairs are separated either by " ;" (space-semicolon) or by new-line except when the closest non-whitespace character before it is a backslash.

Key
---

Keys can be numbers and field names. When separated by new-line, they must be followed by a ':'. When separated by a ' ;', the colon is optional.

If the key is a positive integer, it indicates that data for a step follows. 0 always separates tasks.

Ex: *task A ;0 task B ;1 a step. This is a step of task B =s1 ;1 another step of task B =s2 ;0 task C*

This defines task A, B, and C. Task B has two steps. See that ';1' separator binds tighter than ';0'.
The ';1'-separated chain consists of three elements: Title of task B ("task B"), then the description of step s1 and then the description of step 's2'. The id notation =... is a short form for ';id ...'

Field names can be abbreviated to the shortest string that is uniquely resoluble.

Fields: incr_name_prefix (incr), priority (prio), description (descr; for main step only; for steps/substeps description is the title or vice versa), from_date (from), until_date (until), expoftime (exp), steps (st), done (do), order (ord), archived_because (arch)

Value
-----

 * Priority: label or number

 * Description: Markdown syntax support. Newline and other non-printable special characters can be literal or escaped (\n).

 * Order (of steps): any (default), nx (next step, depends on prior), eq (equal, step does not depend on prior one).

 * Until_date: Date@Trackname. If @trackname is omitted, default is assumed. Date can be either in ISO or in german notation. Year and month ommittable. Also, a relative notation is possible: "+1m1w-1d>Fr" – base date (from_date) plus one month and one week, minus one day, but if it is not a friday, continue up to the next Friday. Year is "y" by the way, you will probably never need it.

 * From_date: If the relative notation is used, the base date is "today".

 * Steps: number

 * Done: number, less than steps.

 * Substeps: Chain of substeps, separated by '/' or '|', ',' and ';' depending on their order. Only meaningful when mentioned only. Ignored i.e. superseeded if substeps are defined with higher-number separated elements.




