What are the settings?
======================

You can show and change your settings by clicking the third icon or the wanted item in the menu pulled down when hovering the item.

Weights of the ranking criteria
-------------------------------

The FlowgencyTM ranking score ("FlowRank") is mathematically just a simple product comprising the following dimensions of urgency. By default, they are equally weighted, but you may adjust that to your liking. Please note: It is of no use changing it too often. The mind will need some time to get accustomed.

Priority levels
---------------

Separate the priority labels by comma. You may chain commas to indicate that the next labeled priority is more than one level higher than the previous. In the priority level field of the task editor, you can assign the priority just as well by number, so these unlabeled in between are usable, too. Count up from left to right, start at 1.

Time model
----------

Tasks are linked to time tracks so FlowgencyTM knows when they are active or when they pause, that is when they rank up according to higher urgency score to reflect need of more checks, just like hungry nestlings cheep for worms. You can define as many tracks as you find necessary to match how you work. The model is very flexible, but beware, an overcomplicated model would confuse you, so would effectively be a productivity hindrance.

If you want to create further tracks, give them distinct names that may not contain space, punctuation or other special characters, only a-z, A-Z, 0-9 and _. Make sure you set a descriptive label by which you can select it in the task editor. Then, set either week_pattern or a week_pattern_of_track to shape the fill-in used initially and in gaps between variations if any. All linkages between tracks are checked for circular dependencies (successor, too).

Variations can have names with the same restriction as for track names. You may set any one of week_pattern, week_pattern_of_track ignoring or section_of_track including variations if any, or ref. If you set none, the properties of track fill-in are implied. Give the variation a description, from_date and until_date at least. In case of ref, however, all properties not mentioned are implied from the referenced variation that must originate in the upper hierarchy of the track.

Task urgency threshold
----------------------

<p>Unless you checked the list option "later", and if at least one of your tasks to do is open, any further closed task is listed only if the following inequation holds true for it: <code style="font-size:125%;background-color:yellow;"><var title="FlowRank score of a closed task">uₜ</var> &gt; <var title="minimum FlowRank score among open tasks">ǔₒ</var> + <var title="coefficient, configured by you, default = 0.1">c</var>⋅(<var title="minimum FlowRank score among open tasks">ǔₒ</var> &minus; <var title="maximum FlowRank score among listed tasks">û</var>)</code>.</p><ul><li><var>uₜ</var>: FlowRank score of a closed task, <var>ǔₒ</var>: minimum FlowRank score among open tasks, <var>û</var>: maximum FlowRank score among listed tasks,</li><li><var>c</var>: coefficient that you can adjust here.

If you put the handle to the left end (=0), closed tasks are never displayed after the least urgent open task. If you drag it to the right end (=1), the FlowRank distance between a closed task and the least urgent open task can be about as much as the distance between the least and the most urgent task.


