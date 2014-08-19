README
======

About FlowTime
--------------

FlowTime is an open-source software tool to structure your tasks and track your progress, and to organize them in order to fit into your reserved working time. It does not look as simple as other tools claim to be, yet it is well-thought-out. Especially f you are prone to and suffer from procrastination, you are welcome to give it a try.

You can divide your tasks into steps, and where necessary, those again into substeps. It is possible to input an estimate about how much more time-expensive one step is in relation to other, so the tool can make calculations more realistic.

FlowTime ranks the tasks by urgency which you can reduce primarily by checking completed steps or, secondarily, by holding off on (soft) due dates if you find controlled procrastination is still better. Tasks you should do "now", as is deduced from that data, are always listed on top when you update the screen by deliberately clicking or touching the FlowTime logo.

Urgency calculation comprises five different indicators. You can bring their weights of influence into whatever relation you find appropriate for you. Except the static priority of a task, the indicators are time-dynamic, which means they rise given a lack of progress in the working time periods you planned and defined in advance. One of them, the drift between time and progress, is additionally reflected in a smooth color gradient bar under the task title blending from green (when task is not as time-consuming as estimated) over the same blue like the FlowTime logo (optimal) to reddish (it will probably climb to the top).

You can have as many different so-called time tracks as you need in parallel. You can even have tasks switch tracks at a future point of time, or couple tracks themselves so all tasks linked to them would switch under the hood. The tracks consist basically of working and off-time periods recurrent on a given n-weekly basis at specified week days. Single ones with different patterns can be embedded. E.g. for your holidays you would define from-what-to-ever 24/7 off and a definition can made devolve to other tracks so you need not to repeat them.

The urgency plateaus, periods of time literally stopped if you will, help you becoming mentally immune against business worries, after all you pay with accordingly steeper an increase of urgency in between. This is what FlowTime might contribute to in the long term: As a kind of a pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and could collapse dramatically someday.

I hope you get more flow experience – hence the name – once this is accomplished, or even sooner because you can focus better on your work as you can focus better on your life. FlowTime is meant to remedy rather fatal "work/life blend" ideology spreading among western digital era corporations.


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

Keep the window open, it will output diagnostics if things go wrong (they will). Then open, in your favourite browser, the link it displays at the end. If you have a local firewall installed, this might not work. Refer to the manual of your firewall software how to make exceptions so that it does (better contact your system administrator, if any).
