What to enter into the fields of the Task editor?
=================================================


Identifier prefix
-----------------

A name for a task is found automatically on creation. Sometimes you may want to provide a prefix consisting of alphabetical characters. If the prefix exists, a number is appended and incremented until the ID is unique. You may suggest the number where the incrementing is to start.

Title
-----

The title is displayed above the colour gradient bar. It should be descriptive, but also as short as yet comprehensible by your future me.

Start date
----------

You need to set it only if you want the task to start at a later date/time.

Time stages
-----------

Associate the task to a time track you can define and modify in the settings, and specify the due date. You may also specify points of time when the task shall change the track.

Description
-----------

If the admin of the FlowgencyTM package has installed the markdown package or, precisely, the Text::Markdown CPAN module (optional; you can do it later but use the syntax already), it is loaded automatically and you can have clickable links, inline emphasis, headings and the like. Please note that heading levels are automatically increased by 3.

See also <https://en.wikipedia.org/wiki/Markdown> or other for a syntax reference.

Expenditure of time share
-------------------------

By how much shall the completion of this step advance the overall progress?
To estimate this value right, imagine the expenditure of time used by the superordinate step (or task, alternatively) as a pie to be shared with all subordinate steps incl. this one and additionally each of its own subordinate steps. The pieces are equal in size but of any number in total. However, you may allocate to this step more than one. When in doubt, better leave the default of 1.

Subordinate steps
-----------------

As this field is currently layed out, it has a ridicule user experience. I know. 

To create steps, just use a new name that you cannot find in the step switcher menu. When a name entered is used already, the according step will be detached from its original parent step and "adopted" by the new parent. If you remove a step, it can be reattached to any other step of the same task. Not before you send off the data, they will be lost.

For naming steps the following characters are allowed: A-Z,a-z,0-9. If you want multiple steps, separate them by one of the following separators, depending on meaning:

  * Use **/** (slash) or **|** (vertical bar) to group steps among which the order of completion is irrelevant.
  * Separate steps or step groups by **,** (comma) to indicate that the order does matter.
  * **;** (semicolon) instead of comma signals a final special group of steps not depending on any other one. Each is always displayed until completed.

Step progress
-------------

This slider is rendered as a chain of checkboxes later. It might be harmonized to the same widget in the future.
 
Archive task
------------

If you enter something in this field, the task is archived even if not all steps are completed, that is it will not show up any more. To view all tasks that have been archived (whether completed or not), please click the link "archive" in the filter menu.

The value 'done' is magic, of no use to set it manually: It is set or cleared by the system depending on whether there are uncompleted steps.

By setting the special value '!PURGE!', you delete the task irrevocably, so be cautious.
