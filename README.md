README
======

![Logo](site/logo/flowgencytm.png)

What is FlowgencyTM? - Seven key-notes
--------------------------------------

 1. FlowgencyTM is a tool to plan and to manage tasks, their urgencies, progresses and dependencies, just for yourself. It is all about getting things done, maybe except those of lowest priority, within the time that you have expressedly reserved for work. In a business world that is fallen for the multitasking illusion, it helps maintaining to-dos in a sequential order and sticking to it, so flow experience is liklier to come.

 2. The user interface is implemented in HTML5 and Javascript, so it runs in your favourite web browser. The server component is included in the distribution, too. It forms an inherent part of it. FlowgencyTM is not meant an online service, it is rather preconfigured to run on your local system from which it exclusively accepts requests.

 3. The tasks are ranked by descending urgency. The ranking is updated when you click the Flowgency logo in the top left edge. You decide when any checks are committed and when you are mentally prepared for being occasionally confronted with other tasks that may have become suddenly more urgent than those you have just been working on.

 4. In FlowgencyTM terms, priority is just one of several urgency dimensions, albeit the only that is directly entered and adjustable afterwards. The software distinguishes four other that depend on time:

   * How near the due date has approached,

   * how much time has elapsed in relation to how much expenditure you have checked as done,

   * for how much time you have been keeping the task open (if at all) and finally

   * how much will the additional time need be compared to what you have originally planned, considering your working speed.

 5. These four increase with advancing time, but not the system clock, FlowgencyTM has got its own that only covers the working time you specify in your time model. In periods of off-time in between, urgency is frozen. Affected i.e. pausing tasks are by default even hidden from display.

 6. You can devide tasks into steps, steps again into substeps. You can build arbitrarily deep hierarchies. Sometimes tasks or steps have substeps you find ridiculous to describe because they go without saying. Then you can instead specify that the software is to provide how many checks ever for them, one for each substep just thought.

 7. It is open source software licensed under the General Public License, version 3 or any later version. It resides on GitHub (URL: https://github.com/flowdy/FlowgencyTM) for you to download and use, or to fork it.

This is how FlowgencyTM looks like on your screen:

![Screenshot](doc/snapshot-home.png)

What it is not
--------------

I, the project initiator and maintainer, *think* I have put into it some quite revolutionary nowhere-else-seen concepts, but really just my ego believes it is the next big thing. At least it is realized in the hope that it is useful for someone.

However, it is not all meant for more than small-scale project management, ignoring management of costs, assets, risks etc. Neither as an enterprise-level groupware solution. But you are welcome to enhance it with interfaces to groupware products for tasks import or the propagation of those done.



How best to benefit from using FlowgencyTM
------------------------------------------

### Define your personal time model

User profiles are created with a default 24/7 time model. This is to avoid tasks to vanish at times, thus confusing the user. It is not meant at all to promote the idea that workoholism is of any good.

Your experience of proper urgency-based ranking requires telling the software beforehand when you plan to work on the entered tasks and when not. With FlowgencyTM, you are to plan your working time roughly in advance. You can always modify your time model for the future (e.g. for holidays), but to touch the past would lead to false results which is why that would lead to an error message.

Don't get that wrong: It is not required (practically it is impossible anyway) to follow your defined time model tightly down to the second. Just the more your actual working times match with what you have planned, of the more use will be FlowgencyTM for you. This asks of you some discipline. To a certain extent, you will have to let go of spontaneity, you have to plan your day and to stick. When you have to go no matter what your plans say, you can have a glance into a future state of your urgency ranking left alone till then, so there will be no nasty surprise when you return.

So define: When are you at work? When do you engage in which job or project? And when are you off, absent from work, which means rather fully present for family, friends, hobbies and stuff? When do you want a *computated* reason to let go of worries related to your work organization, business imponderables drawing circles in your mind? Please note, however, that the amount of working time directly relates to how fast urgencies rise along the way.

The time model system is very flexible in order to allow for hopefully everyone's preferences. For example, when you define a variation (a rhythm bound to a given time span) inside a time track, you can have that variation shared with other tracks specified in the track definition. So you need to define holidays only once in a master track, all subordinate "slave" tracks can automatically adopt them and future changes to them as well.

But then there is a risk of overcomplicating your time model. If you don't understand why task X is unlisted as paused suddenly, this is unfavourable and can reduce your productivity by turning your focus back to time management instead of the tasks themselves. Keep it simple and stupid, and do not tune it all the time. Best change it only to add next holidays or when you are imposed / have agreed upon job structure changes.


### Structure your tasks unless they are simple. Check steps when they are done.

Enter tasks before you do them. Enter even simple ones unless you are certain that doing them right ahead is notably faster than entering them first. In order to enable FlowgencyTM to calculate and rank their urgencies correctly, make sure you take the following questions into consideration:

  * When does a task start if not now, and when is it due?

  * If you have more than one time track, on which do you want to do it?
    That is, when shall they be active and bubbling up in the list in need to be checked?
    Shall they change the time track at given points in time? Even that is possible.

  * Which priorities do they have?

  * Can they be divided into steps and which of those further into substeps perhaps? The hierarchy of steps and substeps can be arbitrarily deep.

  * Do these steps or groups of steps require to be checked in the given or in random order? Steps for which you must do other steps first, are not displayed. You can have also steps to do occasionally in any order, at the latest after having done all ordered steps of a superordinate one or the overall task, respectively.

  * In your rough estimate, how much does a specific step or substep claim of the time-need that the respective superordinate one claims in all? Indicate that by plain relational integers. In the first time you use FlowgencyTM, you probably will want to leave the default of 1, so checks on all neighbouring steps will drive the progress forward by equal extents. But you can, if you want, make progress calculation more realistic by adjusting the expenditure of time shares.

  * How many checks shall a specific step/substep get? Setting a number greater than 1 is like assigning substeps to it without writing a description, estimating their expenditure of time and maybe increasing the number of checks.

Once a task is entered with proper data, and it is displayed somewhere below in the ranking, just forget it and return to the tasks currently on top. Check a step of the tasks at the top right when it is done.

When you want to save the checks and you are mentally prepared to switch to another task that might have become more urgent than what you have been working on: Just deliberately click the FlowgencyTM logo to reorder the tasks by descending urgency as how it is at the time of the click. Tasks of which the associated time track is currently "off" will never raise in urgency while this is the case. In other words, these planned periods of still time are logically identical with the net second before. By default, paused tasks are even hidden from display.

### Commit to and appreciate Humane Information Technology (HIT)

Care for where the server is running, where your data is stored. Your time and how you use it is a rather private thing, and thus should be kept private. I, for one, do not consider FlowgencyTM or any other service inspired thereof a good option if provided commercially or "for free" by some internet company, a cloud provider or even by your own employers' IT department. After all, however, the decision is yours. FlowgencyTM is, due to its purpose, like a knife in your kitchen drawer that you can prepare a meal with as well as stab someone, or being stabbed. The one whose time is managed should be the only one who is managing it.

Even if you are a fan of FlowgencyTM, please understand that the method of time management is a private thing, too. There will be many who choose not to use it and there will always be some who even dislike that you do. To persuade others to use it, to push it in your company, let alone to imply or explicitly threaten your employees with negative consequences if they choose not to, would render all the productivity benefits of the software effectively void. Voluntariness, that is, *real* voluntariness is key. As an employer, you are responsible for having your staff comply with any working hours agreed upon and do the given tasks until any reasonable due dates. Leave them the choice of whether or not to use some time management tool or method, with FlowgencyTM just being an instance of many.


Wherefore all that, what's the vision?
---------------------------------------

On the larger scale, if the software is used by many, this I hope is what FlowgencyTM will contribute to: As a kind of a feedback-driven pacemaker, there will be reliable rhythms of stress and relaxation in a global business life that is presently running amok, overheating more and more and could therefore collapse dramatically someday.

One could doubt, though, software is the right means of help, but in an era of quite religious belief in computers and technology in general (which is something computer pioneer and late technology critic Joseph Weizenbaum made me question), it is high time to teach our computers that we must be off regularly because we are at last who deliver them energy to run. To comply with them in their agnostic 24/7 dictate is idiotic, it is like having our children say what we are to do. Keep in mind, too: Your competitors never sleep, maybe since they suffer burn-out syndrome ;-).

I hope you get more flow experience – hence the name –, because you can focus better on your work as you can focus better on your life. 

The concept in detail
---------------------

This is the summary of the concept that you can read in more detail in doc/concept.en.txt. Those who have got a good command of German might prefer doc/concept.de.txt as it is at times more up-to-date than the english translation.

Installation
-------------

FlowgencyTM is a prototype, yet just a proof-of-concept that can work like a smooth or fail badly, for others as likely as for myself. So you are welcome to use FlowgencyTM with test data! Keep in mind that this software is alpha. This means that crashes and a regularly corrupted database are to be expected. So do not yet use it for vital projects or if you do really cannot help doing, backup often! Please file bug-reports, for which I thank you very much in advance.

FlowgencyTM is implemented in the Perl programming language, version 5.14+. Mac OS X and most linux distributions include it ready for use, ensure it is installed by running the command `perl -v`, or search the web how to install the latest version on your system. Windows users are recommended Strawberry Perl, please download from <http://strawberryperl.com/>.

Clone the git repository in a directory of your choice. With plain git on Linux enter at a shell prompt:

   git clone <https://github.com/flowdy/FlowgencyTM.git>

For other systems, install the Git DVCS and do the according steps (cf. manual).

Check the dependencies
-----------------------

Check and install any prerequisites by running inside the FlowgencyTM directory, provided cpanm tool is installed on your system:

  cpanm --installdeps .


Run the program
----------------

At a shell prompt, under the FlowgencyTM directory, run the command

   script/morbo

Please do not close the terminal window, it will output diagnostics if things go wrong. Then open, in your favourite browser, the link it displays at the end. If you have a local firewall installed, this might not work because of any weird restrictions imposed. Refer to the manual of your firewall software how to make exceptions so that it does let you access your own system via HTTP (better contact your system administrator, if any).


Copyleft and credits
---------------------

(C) 2012, 2013, 2014 Florian Heß

Advisory in logo design: Laura Heß

Contact Author / Project initiator
-----------------------------------

(Address split up for the sake of spam protection. Just glue it together and apply the "@" sign replacing "at".)

    fhess at mailbox. org


License
-------

FlowgencyTM is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

FlowgencyTM is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with FlowgencyTM. If not, see <http://www.gnu.org/licenses/>.

