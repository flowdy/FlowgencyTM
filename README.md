README
======

What is FlowTime?
-----------------

FlowTime is an open-source task and time management tool the frontend of which runs in your favourite HTML5-capable webbrowser. It is not a webservice, however, it just has a built-in server component you can run locally on your own system provided it can (be set up to) run perl programs. Then, access is restricted from the local system itself by default. FlowTime is not intended to be a good groupware solution, however, despite its basic support for team work.

In how does it differ from so many other little programs like that?
-------------------------------------------------------------------

Fundamental to FlowTime is a sophisticated humane concept of working time as opposed to clock time.

As in most other task management applets, the list of pending tasks is ranked by their urgencies. However, while said programs mostly consider two urgency criteria only, a) the priority and/or b) the remaining time until a due-date set by the user, FlowTime calculates a task's urgency by taking into account following additional time-related dimensions.

  * c) the drift between your progress and the time needed so far, relatively,

  * d) if you keep the task open "on desk", for how long you have been doing so,

  * e) the overall time-need as estimated by the tool, relative to the planned overall time-need.

Concerning all four time-related dimensions, the respective indicators increase gradually and make the tasks rise like bubbles in water. So, you may regard the passing time as kind of an antagonist to your continuous checking steps done. 

Of course, however, time in FlowTime is not the time passing through the whole day and night no matter when you are at work and when not. Instead it is the "net" working time interrupted with periods of leisure, private off-time that most psychologists consider too valuable for mental health to sacrifice for the wealth of the company. These periods of "literally still time" have to be planned in advance based on your experience and discipline, and declared in a time model.

The time model can consist of as many different so-called time tracks as you need in parallel. It is somewhat like a model railway: You can even have single tasks switch tracks in the future, or couple tracks themselves so all tasks linked to them would switch under the hood. The tracks consist basically of working and off-time periods (i.e. chunks of machine seconds to the system) recurrent on a given n-weekly basis at specified week days. Single periods with different patterns can be embedded, e.g. for holidays (24/7 off). The urgency plateaus, those periods of literally still time as mentioned, help you becoming mentally immune against business-related worry about how due your tasks have become. Just keep in mind you pay after all with accordingly steeper an increase of urgency in between, so you deserved work-clean leisure.

You can weight the dimensions so their influence on the ranking is appropriate for yourself.

In order to shape your progress more realistically, you can structure tasks into steps and even substeps, where needed. Moreover, you can give an estimate about how much a step claims from the overall time-need relative to what parent, sibling and child steps do, so "done" checks may differ accordingly in how much they add to the progress.

Wherefore all that, what's your vision?
---------------------------------------

On the larger scale, this I hope is what FlowTime will contribute to: As a kind of a pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and could therefore collapse dramatically someday. One could doubt, though, software is the right means of help, but in an era of quite religious belief in computers and technology in general (which is something I question myself, courtesy Joseph Weizenbaum), it is at least a pragmatic and practical approach to remedy rather fatal "work/life blend"¹ ideology spreading among western digital era corporations. It is fatal because by that the employer increasingly invades the employees' private lives, turning them into slaves being either active or in a mental state of alert stand-by mode all their time. Everyone is to decide on his and her own at last: Either one is really off of work regularly and for sufficient time, or one will be forever off someday.

To put it in a nutshell: Your competitors never sleep. Today or tomorrow, they will suffer burn-out.

I hope you get more flow experience – hence the name –, because you can focus better on your work as you can focus better on your life. 

The concept in detail
--------------------------

This is the summary of the concept that you can read in more detail in doc/concept.en.txt. Those who have got a good command of German might prefer doc/concept.de.txt as it is at times more up-to-date than the english translation.

Installation
-------------

FlowTime is a prototype, yet just a proof-of-concept that can work like a smooth or fail badly, for others as likely as for myself. So you are welcome to use FlowTime with test data! Keep in mind that this software is alpha. This means that crashes and a regularly corrupted database are to be expected. So do not yet use it for vital projects or if you do really cannot help doing, backup often! Please file bug-reports, for which I thank you very much in advance.

FlowTime is implemented in the Perl programming language, version 5.14+. Mac OS X and most linux distributions include it ready for use, ensure it is installed by running the command `perl -v`, or search the web how to install the latest version on your system. Windows users are recommended Strawberry Perl, please download from <http://strawberryperl.com/>.

Clone the git repository in a directory of your choice. With plain git on Linux enter at a shell prompt:

   git clone <https://github.com/...>

For other systems, install the Git DVCS and do the according steps.

Check the dependencies
-----------------------

Check and install any prerequisites by running inside the FlowTime directory:

  cpanm --installdeps .

When you make substantial contributions you can get an update on all used modules:

  script/gather_check_dependencies

Please update Makefile.PL accordingly.


Run the program
----------------

At a shell prompt, run the command

   ...

Please do not close the terminal window, it will output diagnostics if things go wrong. Then open, in your favourite browser, the link it displays at the end. If you have a local firewall installed, this might not work because of any weird restrictions imposed. Refer to the manual of your firewall software how to make exceptions so that it does let you access your own system via HTTP (better contact your system administrator, if any).

Entering tasks
--------------

Soon, there will be of course smooth and powerful, javascript-enriched and what not form input available for the user. For core developing and testing purposes however, I did it again: I humbly invented a new syntax to fit my needs. It is optimized for fast-typing, flexibility to allow for different tastes of re-reading, and one-way deserialization of nested task and step data from a plain HTML-field or shell command parameter argument or heredoc input, without your being required to count spaces, parentheses and a like, or to escape quotes (JSON). It leverages the fact that the human brain is used to count with small natural numbers.

But if you *can* write JSON or YAML fast and without errors, and you are reluctant of learning yet another special syntax, just use what you know, either works but without field tag auto-completion and you must yourself gather all steps together, providing a substeps specification for each step that includes substeps. The interpreter behind the task insert/update field will detect the curly or the triple-dash-newline at the beginning and will try to load the respective CPAN module that you have ensured is installed.

### Example of the TreeFromLazyStr syntax

    This is the task title ;description you can apply metadata to it, just append space and semicolon and after it, without space, the metadata field identifier ;from 9-14 ;until 30 10:00@office; 10-10 17:00@labor ;1 This is a substep =foo of the step before, since you incremented the level indicator from 0 to 1 ;1This is another substep on the same level, labeled =bar, it is no problem when you omit the space after the level indicator
     ;2 this is a subsubstep, again do not forget to increment the number of the separator. You can use newline instead of plain whitespace before the semicolon, you can even mix both for indentation, if you want.\nBut escape any literal newline.\
  
    Literal space of any kind is escaped with *one* backslash (\\).
     ;3 the nesting level =three ;4 can be =four ;5 arbitrarily deep, =five ;6: =but don't exaggarate, think well about how many levels match your task. ;1 Mind the motto As simple as possible, as complex as necessary and KISS - keep it simple and stupid.

This is what you would have to input in JSON format:

    {"from_date":"9-14","steps":{"bing":{"substeps":";three","description":"this is a subsubstep, again do not forget to increment the number of the separator. You can use newline instead of plain whitespace before the semicolon, you can even mix both for indentation, if you want.\nBut escape any literal newline. \n  Literal space of any kind is escaped with *one* backslash (\\)."},"four":{"substeps":";five","description":"can be"},"general":{"description":"Mind themotto: As simple as possible, as complex as necessary and KISS - keep it simple and stupid."},"bar":{"substeps":";bing","description":"This is another substep on the same level, labeled, it is no problem when you omit the space after the level indicator"},"but":{"description":"don't exaggarate, think well about how many levels match your task."},"five":{"substeps":";but","description":"arbitrarily deep,"},"three":{"substeps":";four","description":"the nesting level"},"foo":{"description":"This is a substepof the step before, since you incremented the level indicator from 0 to 1"}},"substeps":";foo|bar|general","timestages":[{"until_date":"30 10:00","track":"office"},{"track":"labor","until_date":"10-10 17:00"}],"title":"  This is the task title","description":"you can apply metadata to it, just append space and semicolon and after it, without space, the metadata field identifier"}

And this is the YAML counterpart:

    ---
    description: you can apply metadata to it, just append space and semicolon and after
      it, without space, the metadata field identifier
    from_date: 9-14
    steps:
      bar:
        description: This is another substep on the same level, labeled, it is no problem
          when you omit the space after the level indicator
        substeps: ;bing
      bing:
        description: "this is a subsubstep, again do not forget to increment the number
          of the separator. You can use newline instead of plain whitespace before the
          semicolon, you can even mix both for indentation, if you want.\nBut escape any
          literal newline. \n  Literal space of any kind is escaped with *one* backslash
          (\\)."
        substeps: ;three
      but:
        description: don't exaggarate, think well about how many levels match your task.
      five:
        description: arbitrarily deep,
        substeps: ;but
      foo:
        description: This is a substepof the step before, since you incremented the level
          indicator from 0 to 1
      four:
        description: can be
        substeps: ;five
      general:
        description: 'Mind themotto: As simple as possible, as complex as necessary and
          KISS - keep it simple and stupid.'
      three:
        description: the nesting level
        substeps: ;four
    substeps: ;foo|bar|general
    timestages:
    - track: office
      until_date: 30 10:00
    - track: labor
      until_date: 10-10 17:00
    title: '  This is the task title'

License
-------

FlowTime is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowTime is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowTime. If not, see <http://www.gnu.org/licenses/>.

Footnotes
---------

¹) Sorry, couldn't help looking at and citing you here, Microsoft. "Work-life blend" is, according to the Communications Manager of your German department, currently established in your company culture. To me that seems like a b...ad idea.
