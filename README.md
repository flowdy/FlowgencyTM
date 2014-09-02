README
======

About FlowTime
--------------

FlowTime is an open-source task and time management tool the frontend of which runs in your favourite HTML5-capable webbrowser. It is not a webservice, however, it just has a built-in server component you can run locally on your own system provided it can (be set up to) run perlprograms. Then, access is restricted from the local system itself by default. FlowTime is not intended to be a good groupware solution.

The list of tasks is ranked by their urgency. FlowTime calculates a task's urgency by taking into account several dimensions, which are a) priority, b) the remaining time until the soft due-date or the hard deadline, c) the drift between your progress and the time needed so far, relatively, d) if you keep the task open "on desk" i.e. for how long you have been doing so, e) the overall time-need as estimated by the tool, relative to the planned overall time-need. 

You can weight the dimensions so their influence on the ranking is appropriate for yourself.

In order to shape your progress more realistically, you can structure tasks into steps and even substeps, where needed. Moreover, you can give an estimate about how much a step claims from the overall time-need relative to what parent, sibling and child steps do, so "done" checks may differ accordingly in how much they would add to the progress.

Concerning most urgency dimensions, the respective indicators increase gradually with the time progressing, which you can regard as kind of an antigonist to your continuous checking done steps. Of course, it is not the clock time that runs no matter if you are at work at all. Instead it is is the "net" working time interrupted with periods of leisure and private off-time. These you are to plan in advance based on your experience and discipline, and declared in a time model.

The time model can consist of as many different so-called time tracks as you need in parallel. You can even have single tasks switch tracks in the future, or couple tracks themselves so all tasks linked to them would switch under the hood. The tracks consist basically of working and off-time periods recurrent on a given n-weekly basis at specified week days. Single periods with different patterns can be embedded, e.g. for holidays (24/7 off). The urgency plateaus that you can regard as periods of time literally stopped, help you becoming mentally immune against business-related worry. Just consider that you pay after all with accordingly steeper an increase of urgency in between.

On the larger scale, this I hope is what FlowTime will contribute to: As a kind of a pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and could therefore collapse dramatically someday. One could doubt, though, software is the right means of help, but in an era of belief in computers and technology in general (which is something I question myself, courtesy Joseph Weizenbaum), it is at least a pragmatic and practical approach to remedy rather fatal "work/life blend" ideology spreading among western digital era corporations. It is fatal because by that the employer increasingly invades the employees' private lives, turning them into slaves being either active or in alert stand-by mode all their time. Everyone is to decide on his and her own at last: Either one is really off of work regularly and for sufficient time, or forever someday.

I hope you get more flow experience – hence the name – once this is accomplished, or even sooner because you can focus better on your work as you can focus better on your life. 

This is the summary of the concept that you can read in more detail in doc/concept.en.txt.

Installation
-------------

FlowTime is a prototype, yet just a proof-of-concept that can work like a smooth or fail badly, for others as likely as for myself. So you are welcome to use FlowTime with test data! Keep in mind that this software is alpha. This means that crashes and a regularly corrupted database are to be expected. So do not yet use it for vital projects or if you do really cannot help doing, backup often! File bug-reports, for which I thank you very much in advance.

FlowTime is implemented in the Perl programming language, version 5.12+. Mac OS X and most linux distribution include it ready for use, ensure it is installed the command `perl -v` or search the web how to install the latest version on your system. Windows users are recommended Strawberry Perl, please download from <http://strawberryperl.com/>.

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

Keep the window open, it will output diagnostics if things go wrong (again, as long it is alpha, they will do). Then open, in your favourite browser, the link it displays at the end. If you have a local firewall installed, it might not work because of any restrictions. Refer to the manual of your firewall software how to make exceptions so that it does (better contact your system administrator, if any).
