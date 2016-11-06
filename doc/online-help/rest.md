The REST API
============

Basics
------

The server tells apart REST requests from normal requests by a couple of criteria of which one must match:

 * A HTTP header 'Accept: application/json' always identifies a REST request.
 * So does an HTTP header 'Content-Type' with any value except 'application/x-www-form-urlencoded'.

If the URL called with a REST client requires user authentication, you can either provide that as a session cookie obtained by prior POST to /user/login with user id and password like in the browser interface. You should, however, prefer an Authentication header with following content:

    Basic userId:password

URLs
----

`$...` refers to a placeholder. Please replace it by the id of the wanted object. Items in parentheses have not yet been completely tested.

### `/todo`

 * (GET: List of tasks, by default limited those currently active and urgent. Basic progress data for every task and the currently focussed step when open.)

### `/todo/$task`

 * (GET: Basic progress data for a specific task.)

### `/todo/task-form`

 * (GET: Template for a new task. Supply a &lazystr parameter to have some fields set already.)
 * (POST: = GET, to use with more content that would exceed URL length limit with GET)

### `/tasks`

 * (GET: An array of all tasks, of each the whole record as currently stored in database. )
 * (POST: Batch processes a bunch of new or existing tasks, s. POST or PATCH `/tasks/$task`, respectively. Accepts lazy string text blob or JSON Array or Object. Objects in the array must have a set name property if they are expected to exist. New ones may not have a name, but then an 'incr_prefix_name' key. If the JSON is an object, its properties must be the task name or '_NEW_TASK_$n' with $n being a number that must be unique in a request.)

### `/tasks/$task`

 * (GET: Gets you the whole record of the task.)
 * (POST: Creates a new task. Responds with conflict (409) when the $task id is already forgiven.)
 * (PUT: Defines the fields of the task that are set, and resets the rest. Responds "not found" when $task id does not exist.)
 * (PATCH: define or change any fields of the task. Responds "not found" when $task id does not exist.)
 * (DELETE: Completely erase a task from the cache and the database. It cannot be restored. To just get it out of sight but keep it retrievable, use POST instead and set the `archived_because` field to any value except "done" and "!PURGE!".)

### `/tasks/$task/open`

 * (GET: Reports if a task is currently open, gets you the focussed steps at any rate)
 * (POST: open a task if it is currently closed. Responds with the same DATA as GET)

### `/tasks/$task/close`

 * (POST: Closes a task if it is currently open.))

### `/tasks/$task/form`

 * (GET: = GET `/tasks/task`)
 * (POST: = PATCH `/tasks/$task`)

### `/tasks/$task/analyze`

 * (GET: Extended progress data.)

### `/tasks/$task/steps`

 * (POST: Creates a new step of an existing task. Responds "not found" when $task id does not exist. Responds "conflict" (409) if the field 'name' is already forgiven a step in this task.)

### `/tasks/$task/steps/$step`

 * (GET: Get a specific step from the an existing task. Responds "not found" when the $task or the $step id does not exist.))
 * (POST: Creates a new step of an existing task. Responds "not found" when $task id does not exist. Responds "conflict" (409) if the $step id is already forgiven in this task.)
 * (PUT: Define the fields that are set, and resets the rest. Responds "not found" when $task or $step id does not exist.)
 * (PATCH: Define or change fields of the task step. Responds "not found" when $task or $step id does not exist.)
 * (DELETE: Completely erase a task step from the database. Also drops all substeps and their substeps again.)

### User record manipulation

(TODO).
