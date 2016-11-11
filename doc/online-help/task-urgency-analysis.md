How to understand the information linked by the task urgency score?
===================================================================

The urgency score of a task links to a page with detailed information to explain why the urgency score is so high or low. It consists of three tabs.

Score components
----------------

The *priority* is selected or set by you in the task properties. Priority labels are resolved to their assigned values.

The term "NWT seconds" in the following means seconds within the working periods of the tracks defined in your time model. NWT = "net working time" as opposed to the GT = "Gross Time", all seconds counted likewise i.e. independently from your time model..

The *due* value is indicated in NWT seconds available according your configured time model and the time stages specified in the task properties (s. timeway tab). Its weight should be negative, thus its scale is reversed.

The value *open* is indicated in NWT seconds for which the task has been open.

Both *drift* and *timeneed* result from calculations involving the overall progress of the task (s. progress tab, topmost line starting with ":") in relation to the NWT.

The *drift* indicates by how much the bigger progress of both exceeds the smaller. If the bigger one is the passage of time, the drift is positive, representing the time pressure. Otherwise, if it is the progress, negative. 

The *timeneed* is an estimate based on your current working speed, i.e. extrapolating the drift to all time available. As it considers also the still time, timeneed is actually the relation of the number of real time seconds probably needed for task completion to how many remain till the set due-date.

Progress
--------

The black bullet before a step description indicates that the step appears on the pending list not until all prior steps have been done. The unfilled bullet means that the order of action is less strict, in that the step can be done before or after the preceeding white-bulleted steps up to and including the last black-bulleted one. A dash indicates least strictness: Though displayed at the end, those steps can be done before, after or between the other steps below the same superordinate one.

The percent progress of a step results from the done checks divided by all checks, multiplied with 100% and the number of expenditure of time shares assigned to the step in question. Add the progresses of its direct substeps if any, each multiplied with the respective expenditure of time shares as well. The sum needs then to be divided by the involved expenditure of time shares in total.

Time way
--------

The time way specifies in what periods a task demands your time and when it is paused, i.e. hidden by default.

The net working time values are, like the still absence times in the underlying tooltips, indicated in the format "H:MM:SS".

When a pattern notation in the second column is not prepended with description plus the name of the related variation and its original track (if different), it represents the default/fallback rhythm of the according track.
