README
======

What is FlowTiMeter?
-----------------

FlowTiMeter is a task and time manager. The user interface runs in your favourite webbrowser provided it is capable to render HTML5. All modern browsers do so in 2014.

The back-end server component can (and should at best) be installed on your own local system. By default, it provides access to browsers running on the same system only. You might, prefer to have it hosted by and shared with a trusted friend of yours. Care for where the server is running, as your time and how you use it is a rather private thing, and thus should be kept private. I, personally, do not consider FlowTiMeter or any other service inspired thereof a good option if provided commercially by some internet company, a cloud provider or even by your own employers' IT department. After all, however, the decision is yours. 

With FlowTiMeter, you are to plan your working time roughly in advance. You can always alter your time model for the future, but to touch the past would lead to false results which is why an error message will be displayed.
So define: When are you at work? When do you engage in which job or project? And when are you off, absent from work, which means rather fully present for family, friends, hobbies and stuff, without worries related to your work organization, imponderables stuck in your mind?
The more your actual working times match with what you have planned (100% match is not possible), of the more use will be FlowTiMeter for you.

Enter even tasks, even the simple ones. In order to enable FlowTiMeter to calculate and rank their urgencies correctly, make sure to take into consideration the following questions:

  * When does a task start if not now, and when is it due?

  * On what time track (i.e. job or project) do you want to do it?
    That is, when shall they be active and bubbling up in the list?

  * Which priorities do they have?

  * Can they be devided into steps and which of those further into substeps perhaps? The hierarchy of steps and substeps can be arbitrarily deep.

  * Do these steps or groups of steps require to be checked in the given or in random order? Steps for which you must do other steps first, are not displayed. You can have steps to do occasionally in any order, at the latest after having done all ordered substeps.

  * In your rough estimate, how much does a specific step or substep claim of the time-need that the respective superordinate one claims in all? Indicate that by plain relational integers. In the first time you use FlowTiMeter, you probably will want to leave the default of 1.

  * How many checks shall a specific step/substep get, if not just one?

Once a task is entered with proper data, and it is displayed somewhere below, just forget it and return to the tasks currently on top. Check a step of the tasks at the top right when it is done.

When you want to save the checks and you are mentally prepared to switch to another task that might have become more urgent than what you have been working on: Just deliberately click the FlowTiMeter logo to reorder the tasks by descending urgency as how it is at the time of the click. Tasks of which the associated time track is currently "off" will never raise in urgency while this is the case. In other words, these planned periods of still time are logically identical with the net second before. By default, paused tasks are even hidden from display.

Wherefore all that, what's the vision?
---------------------------------------

On the larger scale, this I hope is what FlowTiMeter will contribute to: As a kind of a feedback-driven pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and could therefore collapse dramatically someday.

One could doubt, though, software is the right means of help, but in an era of quite religious belief in computers and technology in general (which is something Joseph Weizenbaum made me question), it is high time to teach our computers that we must be off regularly because we are at last who deliver them energy to run. To comply with them in their agnostic 24/7 dictate is idiotic, it is like having our children say what to do. Keep in mind, too: Your competitors do not sleep, they suffer burn-out.

I hope you get more flow experience – hence the name –, because you can focus better on your work as you can focus better on your life. 

The concept in detail
--------------------------

This is the summary of the concept that you can read in more detail in doc/concept.en.txt. Those who have got a good command of German might prefer doc/concept.de.txt as it is at times more up-to-date than the english translation.

Installation
-------------

FlowTiMeter is a prototype, yet just a proof-of-concept that can work like a smooth or fail badly, for others as likely as for myself. So you are welcome to use FlowTiMeter with test data! Keep in mind that this software is alpha. This means that crashes and a regularly corrupted database are to be expected. So do not yet use it for vital projects or if you do really cannot help doing, backup often! Please file bug-reports, for which I thank you very much in advance.

FlowTiMeter is implemented in the Perl programming language, version 5.14+. Mac OS X and most linux distributions include it ready for use, ensure it is installed by running the command `perl -v`, or search the web how to install the latest version on your system. Windows users are recommended Strawberry Perl, please download from <http://strawberryperl.com/>.

Clone the git repository in a directory of your choice. With plain git on Linux enter at a shell prompt:

   git clone <https://github.com/...>

For other systems, install the Git DVCS and do the according steps.

Check the dependencies
-----------------------

Check and install any prerequisites by running inside the FlowTiMeter directory:

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

### Simple example of a task definition

    Write an email to boss ;desc tell him that client X will subscribe\
    contract in late November ;pri soon ;until 10-9


### Full Example of the TreeFromLazyStr syntax

**Please note:** This is expert, for contributors and developers only. Normal users are to enter not so simple task data in the form provided soon.

If you *can* already write JSON or YAML fast and without errors, and you are reluctant of learning yet another special syntax, you are welcome to use what you know. Either works, albeit without field tag auto-completion and you must gather together all steps yourself providing a substeps specification for each step that includes substeps.

The interpreter behind the task insert/update field will detect the curly or the triple-dash-newline at the beginning and will try to load the respective CPAN module that you must have ensured is installed.

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

FlowTiMeter is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowTiMeter is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowTiMeter. If not, see <http://www.gnu.org/licenses/>.

